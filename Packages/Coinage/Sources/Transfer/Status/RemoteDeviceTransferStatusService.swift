import AsyncExtensions
import DurableTransactions
import Foundation
import NovaCrypto
import SDKLogger
import SubstrateSdk

/// What the finalized chain shows for a coin another device handed off. `gone` means it was there once, so the
/// peer (or a recall from here) took it; a coin never seen can't be told apart from one never minted.
public enum RemoteDeviceTransferCoinState: Equatable, Sendable {
    case notSeen
    case onChain(exponent: Int16)
    case gone(exponent: Int16)
}

/// Status of a transfer sent from another device of this user. The mint ran there, so nothing local says
/// whether it failed; only the finalized chain is consulted.
public protocol RemoteDeviceTransferStatusServicing: Sendable {
    /// `coinKeys` are the secret keys carried in the transfer memo; their public keys are derived here.
    func subscribeStatuses(coinKeys: [Data]) -> AnyAsyncSequence<[PublicKey: RemoteDeviceTransferCoinState]>
}

public final class RemoteDeviceTransferStatusService: RemoteDeviceTransferStatusServicing, @unchecked Sendable {
    private let chainViewFactory: any PinnedChainViewFactoryProtocol
    private let chainId: ChainId
    private let coinOnChainQuery: any CoinOnChainQuerying
    private let snKeyFactory: any SNKeyFactoryProtocol
    private let logger: SDKLoggerProtocol?

    init(
        chainViewFactory: any PinnedChainViewFactoryProtocol,
        chainId: ChainId,
        coinOnChainQuery: any CoinOnChainQuerying,
        snKeyFactory: any SNKeyFactoryProtocol,
        logger: SDKLoggerProtocol?
    ) {
        self.chainViewFactory = chainViewFactory
        self.chainId = chainId
        self.coinOnChainQuery = coinOnChainQuery
        self.snKeyFactory = snKeyFactory
        self.logger = logger
    }

    /// Re-read on every finalized head; a head that can't be read is skipped, not fatal.
    public func subscribeStatuses(coinKeys: [Data]) -> AnyAsyncSequence<[PublicKey: RemoteDeviceTransferCoinState]> {
        let requested = coinKeys.compactMap { try? snKeyFactory.createPublicKey(fromSecret: $0).rawData() }
        guard !requested.isEmpty else {
            return AsyncStream<[PublicKey: RemoteDeviceTransferCoinState]> { $0.finish() }.eraseToAnyAsyncSequence()
        }

        // The leading tick reads the chain before any head arrives.
        let finalizedHeads = chainViewFactory.finalizedHeads(chainId: chainId).prepend(0)

        return AsyncThrowingStream<[PublicKey: RemoteDeviceTransferCoinState], Error> { continuation in
            let task = Task { [self] in
                var seen: [PublicKey: Int16] = [:]

                do {
                    for try await _ in finalizedHeads {
                        guard let present = await presentAtFinalized(requested) else { continue }
                        continuation.yield(Self.states(of: requested, present: present, seen: &seen))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .removeDuplicates()
        .eraseToAnyAsyncSequence()
    }
}

private extension RemoteDeviceTransferStatusService {
    static func states(
        of keys: [PublicKey],
        present: [PublicKey: Int16],
        seen: inout [PublicKey: Int16]
    ) -> [PublicKey: RemoteDeviceTransferCoinState] {
        seen.merge(present) { _, new in new }

        return keys.reduce(into: [:]) { result, key in
            if let exponent = present[key] {
                result[key] = .onChain(exponent: exponent)
            } else if let exponent = seen[key] {
                result[key] = .gone(exponent: exponent)
            } else {
                result[key] = .notSeen
            }
        }
    }

    func presentAtFinalized(_ keys: [PublicKey]) async -> [PublicKey: Int16]? {
        do {
            let view = try await chainViewFactory.pin(chainId: chainId)
            let responses = try await coinOnChainQuery.fetchCoins(for: keys, atBlockHash: view.finalizedHead.hash)
            guard responses.count == keys.count else { return nil }

            return Swift.zip(keys, responses).reduce(into: [:]) { result, pair in
                if let coin = pair.1 {
                    result[pair.0] = Int16(coin.value)
                }
            }
        } catch {
            logger?.warning("Remote transfer status read skipped: \(error)")
            return nil
        }
    }
}
