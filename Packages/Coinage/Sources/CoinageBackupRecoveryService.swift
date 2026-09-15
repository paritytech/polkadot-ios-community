import AsyncExtensions
import Foundation
import SDKLogger
import SubstrateSdk

// MARK: - Protocol

public protocol CoinageBackupRecoveryServicing: Sendable {
    func subscribeProgress() -> AnyAsyncSequence<BackupProgress>

    /// The launch pass: lists the seed's installations in the contract and gap-scans every previous one
    /// whose initial scan has not completed.
    func start() async

    /// Another look, `deepSearchBatchCount` batches past every previous installation's cursor.
    func deepSearch() async

    /// The user accepted the recovered balance.
    func markAsCompleted() async
}

// MARK: - Implementation

/// Recovers balance held under the subtrees of this seed's previous installations.
///
/// Only ever reads them: a coin found here is spendable, but new keys are allocated in the current
/// installation alone, so nothing found here can move the index this installation hands out next.
actor CoinageBackupRecoveryService: CoinageBackupRecoveryServicing {
    enum Config {
        static let batchSize: UInt32 = 500
        static let emptyBatchCount = 4
        static let deepSearchBatchCount = 10
    }

    private let installationRepository: any CoinageInstallationRepositoryProtocol
    private let configProvider: any AccountDataStoreConfigProviding
    private let dataStoreRepository: any AccountDataStoreRepositoryProtocol
    private let scanner: any InstallationAssetScanning
    private let assetStore: any RecoveredAssetStoring
    private let completedStore: any DeepRecoveryCompletedStoring
    private let logger: (any SDKLoggerProtocol)?

    private nonisolated let progress = AsyncCurrentValueSubject<BackupProgress>(.unknown)

    init(
        installationRepository: any CoinageInstallationRepositoryProtocol,
        configProvider: any AccountDataStoreConfigProviding,
        dataStoreRepository: any AccountDataStoreRepositoryProtocol,
        scanner: any InstallationAssetScanning,
        assetStore: any RecoveredAssetStoring,
        completedStore: any DeepRecoveryCompletedStoring,
        logger: (any SDKLoggerProtocol)?
    ) {
        self.installationRepository = installationRepository
        self.configProvider = configProvider
        self.dataStoreRepository = dataStoreRepository
        self.scanner = scanner
        self.assetStore = assetStore
        self.completedStore = completedStore
        self.logger = logger
    }

    nonisolated func subscribeProgress() -> AnyAsyncSequence<BackupProgress> {
        progress.eraseToAnyAsyncSequence()
    }

    func start() async {
        await recoverNewInstallations()
    }

    func deepSearch() async {
        guard !progress.value.isInProgress else { return }
        progress.send(.deep(.syncing))

        let previous = await previousInstallations()
        var recovered: [RecoveredAssets] = []
        for installation in previous {
            await recovered.append(scan(installation, limit: .batches(Config.deepSearchBatchCount)))
        }
        logger?.info("Deep recovery finished: \(recovered.describe()) across \(previous.count) installation(s)")

        progress.send(.deep(.completed))
    }

    func markAsCompleted() async {
        guard !progress.value.isInProgress else { return }
        await completedStore.setDeepRecoveryCompleted(true)
        progress.send(.completed)
    }
}

// MARK: - Launch pass

private extension CoinageBackupRecoveryService {
    func recoverNewInstallations() async {
        await discoverRegisteredInstallations()

        let previous = await previousInstallations()
        let pending = previous.filter { !$0.initialScanCompleted }

        if pending.isEmpty {
            logger?.info("Recovery: nothing new to scan, \(previous.count) previous installation(s) already scanned")
        } else {
            logger?.info("Recovery: scanning \(pending.count) of \(previous.count) previous installation(s)")
            progress.send(.initial(.syncing))

            var recovered: [RecoveredAssets] = []
            for installation in pending {
                await recovered.append(initialScan(installation))
            }
            logger?.info("Recovery finished: \(recovered.describe()) across \(pending.count) installation(s)")

            // Newly found balance is worth another look, even if the last one was acknowledged.
            await completedStore.setDeepRecoveryCompleted(false)
        }

        if await completedStore.isDeepRecoveryCompleted() || previous.isEmpty {
            progress.send(.completed)
        } else {
            progress.send(.initial(.completed))
        }
    }

    /// A failed read only delays discovery: installations found on an earlier launch are still scanned.
    func discoverRegisteredInstallations() async {
        guard let contract = await configProvider.contractAddress() else {
            logger?
                .warning(
                    "Recovery: data store contract address is not available, scanning the installations already known"
                )
            return
        }
        do {
            let registered = try await dataStoreRepository.fetchRegisteredInstallations(contract: contract, at: nil)
            logger?.info("Recovery: contract lists \(registered.count) installation(s) for this seed")
            try await installationRepository.addPrevious(Array(registered))
        } catch {
            logger?
                .warning("Recovery: could not read registered installations, scanning the ones already known: \(error)")
        }
    }

    func previousInstallations() async -> [PreviousInstallation] {
        do {
            return try await installationRepository.getPrevious()
        } catch {
            logger?.error("Recovery: could not read previous installations: \(error)")
            return []
        }
    }

    func initialScan(_ installation: PreviousInstallation) async -> RecoveredAssets {
        let recovered = await scan(installation, limit: .untilGap)
        logger?.info("Recovery: installation=\(installation.id.logId) \(recovered.describe())")

        if recovered.isComplete {
            do {
                try await installationRepository.markInitialScanCompleted(installation.id)
            } catch {
                logger?.error("Recovery: could not mark installation=\(installation.id.logId) as scanned: \(error)")
            }
        }
        return recovered
    }
}

// MARK: - Gap scan

private extension CoinageBackupRecoveryService {
    enum ScanLimit {
        case untilGap
        case batches(Int)

        func isReached(batches: Int, emptyBatchesInARow: Int) -> Bool {
            switch self {
            case .untilGap: emptyBatchesInARow >= Config.emptyBatchCount
            case let .batches(count): batches >= count
            }
        }
    }

    struct GapScanResult {
        let nextIndex: UInt32
        let found: Int
    }

    /// A failed scan counts nothing and leaves the installation for the next launch to finish.
    struct RecoveredAssets {
        let coins: Result<Int, Error>
        let vouchers: Result<Int, Error>

        var isComplete: Bool {
            if case .success = coins, case .success = vouchers { return true }
            return false
        }

        func describe() -> String {
            "coins=\(Self.describe(coins)) vouchers=\(Self.describe(vouchers))"
        }

        private static func describe(_ result: Result<Int, Error>) -> String {
            (try? result.get()).map(String.init) ?? "failed"
        }
    }

    func scan(_ installation: PreviousInstallation, limit: ScanLimit) async -> RecoveredAssets {
        async let coins = gapScanCoins(installation.id, from: installation.coinScanNextIndex, limit: limit)
        async let vouchers = gapScanVouchers(installation.id, from: installation.voucherScanNextIndex, limit: limit)
        return await RecoveredAssets(coins: coins, vouchers: vouchers)
    }

    func gapScanCoins(
        _ installation: CoinageInstallationId,
        from startIndex: UInt32,
        limit: ScanLimit
    ) async -> Result<Int, Error> {
        let scanned = await gapScan(from: startIndex, limit: limit) { [scanner, assetStore] batchStart in
            let coins = try await scanner.scanCoins(
                installation: installation,
                startIndex: batchStart,
                count: Config.batchSize
            )
            try await assetStore.saveNew(coins: coins)
            return coins.count
        }
        return await scanned
            .mapError { error in
                logger?.error("Recovery: coin scan of installation=\(installation.logId) failed: \(error)")
                return error
            }
            .asyncMap { result in
                try? await installationRepository.updateCoinScanNextIndex(result.nextIndex, for: installation)
                return result.found
            }
    }

    func gapScanVouchers(
        _ installation: CoinageInstallationId,
        from startIndex: UInt32,
        limit: ScanLimit
    ) async -> Result<Int, Error> {
        let scanned = await gapScan(from: startIndex, limit: limit) { [scanner, assetStore] batchStart in
            let vouchers = try await scanner.scanVouchers(
                installation: installation,
                startIndex: batchStart,
                count: Config.batchSize
            )
            try await assetStore.saveNew(vouchers: vouchers)
            return vouchers.count
        }
        return await scanned
            .mapError { error in
                logger?.error("Recovery: voucher scan of installation=\(installation.logId) failed: \(error)")
                return error
            }
            .asyncMap { result in
                try? await installationRepository.updateVoucherScanNextIndex(result.nextIndex, for: installation)
                return result.found
            }
    }

    func gapScan(
        from startIndex: UInt32,
        limit: ScanLimit,
        scanBatch: (_ batchStart: UInt32) async throws -> Int
    ) async -> Result<GapScanResult, Error> {
        var nextIndex = startIndex
        var batches = 0
        var emptyBatchesInARow = 0
        var found = 0

        while !limit.isReached(batches: batches, emptyBatchesInARow: emptyBatchesInARow) {
            let foundInBatch: Int
            do {
                foundInBatch = try await scanBatch(nextIndex)
            } catch {
                return .failure(error)
            }

            found += foundInBatch
            emptyBatchesInARow = foundInBatch > 0 ? 0 : emptyBatchesInARow + 1
            batches += 1
            nextIndex += Config.batchSize
        }

        return .success(GapScanResult(nextIndex: nextIndex, found: found))
    }
}

private extension [CoinageBackupRecoveryService.RecoveredAssets] {
    func describe() -> String {
        let coins = reduce(0) { $0 + ((try? $1.coins.get()) ?? 0) }
        let vouchers = reduce(0) { $0 + ((try? $1.vouchers.get()) ?? 0) }
        let failed = filter { !$0.isComplete }.count

        return "\(coins) coin(s) and \(vouchers) voucher(s) recovered"
            + (failed > 0 ? ", \(failed) installation(s) incomplete" : "")
    }
}

private extension Result where Failure == Error {
    func asyncMap<NewSuccess>(_ transform: (Success) async -> NewSuccess) async -> Result<NewSuccess, Error> {
        switch self {
        case let .success(value): await .success(transform(value))
        case let .failure(error): .failure(error)
        }
    }
}
