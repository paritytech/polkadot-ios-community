import Foundation
import os
import Testing
@testable import Coinage

struct CoinageBackupRecoveryServiceTests {
    private static let batchSize: UInt32 = 500
    private static let emptyBatches: UInt32 = 4
    private static let deepBatches: UInt32 = 10
    private static let previous = CoinageInstallationId.fixed(0x01)
    private static let anotherPrevious = CoinageInstallationId.fixed(0x02)

    private let installations = InMemoryInstallations(current: .test)
    private let dataStore = StubDataStoreRepository()
    private let scanner = StubScanner()
    private let assetStore = RecordingAssetStore()
    private let completed = InMemoryFlag()
    private let service: CoinageBackupRecoveryService

    init() {
        service = CoinageBackupRecoveryService(
            installationRepository: installations,
            configProvider: StubDataStoreConfig(),
            dataStoreRepository: dataStore,
            scanner: scanner,
            assetStore: assetStore,
            completedStore: completed,
            logger: nil
        )
    }

    @Test("the current installation is never scanned")
    func currentNeverScanned() async throws {
        dataStore.listed([.test, Self.previous])

        await service.start()

        #expect(scanner.scannedInstallations == [Self.previous])
    }

    @Test("coins found under a previous installation keep that installation and their absolute index")
    func recoveredCoinsKeepIndex() async throws {
        dataStore.listed([Self.previous])
        scanner.coinsOnChain = [CoinageKeyIndex(installation: Self.previous, item: 1_234)]

        await service.start()

        #expect(assetStore.savedCoins.map(\.derivationIndex) == [CoinageKeyIndex(
            installation: Self.previous,
            item: 1_234
        )])
    }

    @Test("the scan stops after four empty batches in a row, not four in total")
    func gapRule() async throws {
        dataStore.listed([Self.previous])
        // Non-empty batches 0, 3 and 6; with a counter that never reset, batch 6 would be missed.
        scanner.coinsOnChain = Set([10, 1_600, 3_100].map { CoinageKeyIndex(installation: Self.previous, item: $0) })

        await service.start()

        #expect(assetStore.savedCoins.map(\.derivationIndex.item) == [10, 1_600, 3_100])
        let expectedNext = 3_100 / Self.batchSize * Self.batchSize + (Self.emptyBatches + 1) * Self.batchSize
        #expect(installations.previous(Self.previous)?.coinScanNextIndex == expectedNext)
    }

    @Test("a scanned installation is not scanned again on the next launch")
    func scannedOnce() async throws {
        dataStore.listed([Self.previous])
        await service.start()
        scanner.clearScanned()

        await service.start()

        #expect(scanner.scannedInstallations.isEmpty)
    }

    @Test("an installation registered after the last launch is scanned on this one")
    func newInstallationScanned() async throws {
        dataStore.listed([Self.previous])
        await service.start()
        scanner.clearScanned()

        dataStore.listed([Self.previous, Self.anotherPrevious])
        await service.start()

        #expect(scanner.scannedInstallations == [Self.anotherPrevious])
    }

    @Test("a failed contract read still scans installations already known")
    func failedContractRead() async throws {
        try await installations.addPrevious([Self.previous])
        dataStore.failing()

        await service.start()

        #expect(scanner.scannedInstallations == [Self.previous])
    }

    @Test("an installation whose scan failed is retried on the next launch")
    func failedScanRetried() async throws {
        dataStore.listed([Self.previous])
        scanner.failing = true
        await service.start()
        #expect(installations.previous(Self.previous)?.initialScanCompleted == false)

        scanner.failing = false
        await service.start()

        #expect(installations.previous(Self.previous)?.initialScanCompleted == true)
    }

    @Test("with previous installations recovered the user is asked to confirm the balance")
    func asksToConfirm() async throws {
        dataStore.listed([Self.previous])

        await service.start()

        #expect(try await progress() == .initial(.completed))
    }

    @Test("with nothing to recover there is nothing to confirm")
    func nothingToConfirm() async throws {
        dataStore.listed([.test])

        await service.start()

        #expect(try await progress() == .completed)
        #expect(assetStore.savedCoins.isEmpty)
    }

    @Test("deep search continues every previous installation from where it stopped")
    func deepSearch() async throws {
        dataStore.listed([Self.previous, Self.anotherPrevious])
        await service.start()
        let resumeFrom = try #require(installations.previous(Self.previous)?.coinScanNextIndex)

        await service.deepSearch()

        let expected = resumeFrom + Self.deepBatches * Self.batchSize
        #expect(installations.previous(Self.previous)?.coinScanNextIndex == expected)
        #expect(installations.previous(Self.anotherPrevious)?.coinScanNextIndex == expected)
        #expect(try await progress() == .deep(.completed))
    }

    @Test("accepting the balance completes recovery until a new installation is found")
    func markAsCompleted() async throws {
        dataStore.listed([Self.previous])
        await service.start()

        await service.markAsCompleted()
        #expect(try await progress() == .completed)

        dataStore.listed([Self.previous, Self.anotherPrevious])
        await service.start()
        #expect(try await progress() == .initial(.completed))
    }
}

private extension CoinageBackupRecoveryServiceTests {
    func progress() async throws -> BackupProgress? {
        for try await progress in service.subscribeProgress() {
            return progress
        }
        return nil
    }
}

// MARK: - Fakes

private final class StubScanner: InstallationAssetScanning, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(
        coins: Set<CoinageKeyIndex>,
        failing: Bool,
        scanned: [CoinageInstallationId]
    )>(
        initialState: ([], false, [])
    )

    var coinsOnChain: Set<CoinageKeyIndex> {
        get { state.withLock { $0.coins } }
        set { state.withLock { $0.coins = newValue } }
    }

    var failing: Bool {
        get { state.withLock { $0.failing } }
        set { state.withLock { $0.failing = newValue } }
    }

    /// Distinct, in first-seen order.
    var scannedInstallations: [CoinageInstallationId] {
        state.withLock { scanned in
            var seen: Set<CoinageInstallationId> = []
            return scanned.scanned.filter { seen.insert($0).inserted }
        }
    }

    func clearScanned() {
        state.withLock { $0.scanned = [] }
    }

    func scanCoins(installation: CoinageInstallationId, startIndex: UInt32, count: UInt32) async throws -> [Coin] {
        let (coins, failing) = state.withLock { state -> (Set<CoinageKeyIndex>, Bool) in
            state.scanned.append(installation)
            return (state.coins, state.failing)
        }
        if failing { throw InstallationStubError.nodeWentAway }

        return (startIndex ..< startIndex + count)
            .map { CoinageKeyIndex(installation: installation, item: $0) }
            .filter { coins.contains($0) }
            .map { key in
                Coin(
                    exponent: 1,
                    derivationIndex: key,
                    age: 0,
                    isOnchain: true,
                    publicKey: Data([UInt8(truncatingIfNeeded: key.item)])
                )
            }
    }

    func scanVouchers(
        installation: CoinageInstallationId,
        startIndex _: UInt32,
        count _: UInt32
    ) async throws -> [Voucher] {
        let failing = state.withLock { state -> Bool in
            state.scanned.append(installation)
            return state.failing
        }
        if failing { throw InstallationStubError.nodeWentAway }
        return []
    }
}

private final class RecordingAssetStore: RecoveredAssetStoring, @unchecked Sendable {
    private let coins = OSAllocatedUnfairLock<[Coin]>(initialState: [])

    var savedCoins: [Coin] { coins.withLock { $0 } }

    func saveNew(coins: [Coin]) async throws {
        self.coins.withLock { $0.append(contentsOf: coins) }
    }

    func saveNew(vouchers _: [Voucher]) async throws {}
}

private final class InMemoryFlag: DeepRecoveryCompletedStoring, @unchecked Sendable {
    private let value = OSAllocatedUnfairLock(initialState: false)

    func isDeepRecoveryCompleted() async -> Bool { value.withLock { $0 } }

    func setDeepRecoveryCompleted(_ completed: Bool) async {
        value.withLock { $0 = completed }
    }
}
