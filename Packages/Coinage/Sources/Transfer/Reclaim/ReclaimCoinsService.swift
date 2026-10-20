import AsyncAlgorithms
import AsyncExtensions
import Foundation
import FoundationExt
import NovaCrypto
import SDKLogger
import SubstrateSdk

/// Takes back the handed-off coins of a payment that no peer claimed, each into a fresh coin of ours.
///
/// Decides only which coins are reclaimable. When the claim window has closed is the caller's call.
public protocol ReclaimCoinsServicing: Sendable {
    /// Schedules a reclaim of every coin of the payment still unclaimed. Returns once they are registered,
    /// not once they settle. Schedules nothing when no coin qualifies.
    func reclaim(coinKeys: [Data], groupId: CoinageTxGroupId) async throws

    /// The coins whose reclaim failed in `groupId` and was not followed by a later attempt.
    func subscribeFailedReclaims(groupId: CoinageTxGroupId) -> AnyAsyncSequence<Set<PublicKey>>
}

public final class ReclaimCoinsService: ReclaimCoinsServicing, @unchecked Sendable {
    private let txService: any CoinageTxServicing
    private let databaseFactory: any DatabaseDependencyFactoring
    private let minter: any CoinMinting
    private let snKeyFactory: any SNKeyFactoryProtocol
    private let dateProvider: any DateProviding
    private let logger: SDKLoggerProtocol?

    init(
        txService: any CoinageTxServicing,
        databaseFactory: any DatabaseDependencyFactoring,
        minter: any CoinMinting,
        snKeyFactory: any SNKeyFactoryProtocol,
        dateProvider: any DateProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.txService = txService
        self.databaseFactory = databaseFactory
        self.minter = minter
        self.snKeyFactory = snKeyFactory
        self.dateProvider = dateProvider
        self.logger = logger
    }

    public func reclaim(coinKeys: [Data], groupId: CoinageTxGroupId) async throws {
        let keys = coinKeys.compactMap { try? snKeyFactory.createPublicKey(fromSecret: $0).rawData() }
        var snapshots = databaseFactory.makeTrackedCoinSnapshotStream(publicKeys: keys).makeAsyncIterator()
        let tracked = try await snapshots.next() ?? []

        let reclaimable = tracked.filter(Self.isReclaimable).map(\.coin)
        guard !reclaimable.isEmpty else {
            logger?.debug("Reclaim: nothing to reclaim group=\(groupId)")
            return
        }

        let now = await dateProvider.read()
        var requests: [CoinageScheduledTxRequest] = []
        for coin in reclaimable {
            try await requests.append(request(for: coin, bundleSize: reclaimable.count, now: now))
        }

        logger?.debug("Scheduling \(requests.count) reclaim(s) group=\(groupId)")
        try await txService.scheduleTransactions(requests, groupId: groupId)
    }

    public func subscribeFailedReclaims(groupId: CoinageTxGroupId) -> AnyAsyncSequence<Set<PublicKey>> {
        txService.subscribeOperationGroupStatuses(groupId)
            .map { ReclaimCoinsService.failedInputKeys(of: $0) }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }
}

private extension ReclaimCoinsService {
    /// Committed to the statement store, on chain and never consumed by anything else — the only coins a
    /// reclaim may spend.
    static func isReclaimable(_ tracked: TrackedCoin) -> Bool {
        tracked.coin.isOnchain
            && tracked.coin.handoffMark == .committed
            && tracked.state.consumerStatus == nil
    }

    static func failedInputKeys(of entries: [CoinageTxEntry]) -> Set<PublicKey> {
        let failed = inputKeys(of: entries.filter { $0.status == .failure })
        let succeeded = inputKeys(of: entries.filter { $0.status != .failure })
        return failed.subtracting(succeeded)
    }

    static func inputKeys(of entries: [CoinageTxEntry]) -> Set<PublicKey> {
        Set(entries.flatMap { $0.inputs.map(\.publicKey) })
    }

    /// Mints the destination before scheduling, so the row can link its output, as the claim does.
    func request(for coin: Coin, bundleSize: Int, now: Date) async throws -> CoinageScheduledTxRequest {
        let destination = try await minter.mintCoin(
            exponent: coin.exponent,
            provenance: .reclaimed(from: coin, bundleSize: bundleSize)
        )
        let policy = try CoinageSubmissionParams.reclaimPolicy(
            TransferSubmissionParams(
                buildUntil: now.addingTimeInterval(CoinageConstants.reclaimRetryWindow),
                retryFailures: true
            )
        )

        return CoinageScheduledTxRequest(
            policy: policy,
            inputs: [.coin(.reclaimed(coin.derivationIndex, coin.publicKey))],
            outputs: [.coin(destination.derivationIndex, destination.publicKey)]
        )
    }
}
