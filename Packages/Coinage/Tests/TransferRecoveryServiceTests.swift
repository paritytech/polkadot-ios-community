import Testing
import Foundation
import SubstrateSdk
import KeyDerivation

@testable import Coinage

@Suite("Transfer recovery tests")
struct TransferRecoveryServiceTests {
    private let now = Date()
    // Mocks are NSLock-guarded (@unchecked Sendable) or actors — safe for concurrent recovery.
    // Swift Testing creates a fresh struct instance per @Test, so no state leaks between tests.
    private let walStore = MockTransferWALStore()
    private let coinService = MockCoinService()
    private let voucherService = MockVoucherService()
    private let coinQuery = MockCoinOnChainQuery()
    private let voucherQuery = MockVoucherOnChainQuery()
    private let coinKeyFactory = MockCoinKeyFactory()
    private let voucherKeyFactory = MockVoucherKeyFactory()
    private let blockNumberProvider = MockBlockNumberProvider()

    private func makeService() -> TransferRecoveryService {
        TransferRecoveryService(
            walStore: walStore,
            coinService: coinService,
            voucherService: voucherService,
            coinQuery: coinQuery,
            voucherQuery: voucherQuery,
            coinKeyFactory: coinKeyFactory,
            voucherKeyFactory: voucherKeyFactory,
            blockNumberProvider: blockNumberProvider,
            logger: nil
        )
    }

    /// Convenience WAL entry builder.
    ///
    /// `checkpointBlock` default matches `MockBlockNumberProvider.blockHash` (`Data(repeating: 0x00, count: 32)`)
    /// Pass `.pending` when extrinsic was never broadcast.
    private func makeWALEntry(
        inputCoinIds: [String] = [],
        inputVoucherIds: [String] = [],
        expectedCoinIndices: [UInt32] = [100],
        checkpointBlock: CheckpointBlock = .known(number: 5, hash: Data(repeating: 0x00, count: 32)),
        mortality: UInt32 = 64
    ) -> TransferWALEntry {
        TransferWALEntry(
            inputCoinIds: inputCoinIds,
            inputVoucherIds: inputVoucherIds,
            expectedCoinIndices: expectedCoinIndices,
            checkpointBlock: checkpointBlock,
            mortality: mortality,
            createdAt: now
        )
    }

    private func makeVoucher(
        exponent: Int16 = 3,
        derivationIndex: UInt32,
        recyclerIndex: UInt32 = 0,
        localState: Voucher.State = .pendingTransfer
    ) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: now,
            readyAt: now.addingTimeInterval(3_600),
            remoteState: .inRecycler(Voucher.Recycler(index: recyclerIndex)),
            localState: localState
        )
    }

    // MARK: - Extrinsic confirmed, DB write never ran (split operation)

    @Test("Split operation with confirmed extrinsic writes coins and marks inputs spent")
    func splitConfirmed() async throws {
        let walEntry = makeWALEntry(inputCoinIds: ["99"], expectedCoinIndices: [100, 101])

        walStore.fetchAllResult = [walEntry]
        coinQuery.fetchCoinsResults = [
            CoinSyncResult.OnChainCoin(value: 3, age: 0),
            CoinSyncResult.OnChainCoin(value: 3, age: 0)
        ]

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(coinService.savedCoins == [
            Coin(exponent: 3, derivationIndex: 100, age: 0),
            Coin(exponent: 3, derivationIndex: 101, age: 0)
        ])
        #expect(coinService.markedSpentIds == ["99"])
        #expect(voucherService.deletedIdentifiers.isEmpty)
    }

    // MARK: - Extrinsic confirmed, DB write never ran (unload operation)

    @Test("Unload operation with confirmed extrinsic writes coins, deletes vouchers, marks inputs")
    func unloadConfirmed() async throws {
        let walEntry = makeWALEntry(
            inputVoucherIds: ["v1", "v2"],
            expectedCoinIndices: [200, 201],
            checkpointBlock: .known(number: 10, hash: Data(repeating: 0x00, count: 32))
        )

        walStore.fetchAllResult = [walEntry]
        coinQuery.fetchCoinsResults = [
            CoinSyncResult.OnChainCoin(value: 4, age: 5),
            CoinSyncResult.OnChainCoin(value: 4, age: 5)
        ]

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(coinService.savedCoins.count == 2)
        #expect(coinService.markedSpentIds.isEmpty)
        #expect(Set(voucherService.deletedIdentifiers) == Set(["v1", "v2"]))
    }

    // MARK: - Extrinsic never broadcast

    @Test("Never broadcast extrinsic reverts inputs to available")
    func neverBroadcast() async throws {
        let walEntry = makeWALEntry(
            inputCoinIds: ["99"],
            checkpointBlock: .pending
        )

        walStore.fetchAllResult = [walEntry]
        // Call 1: output probe for index 100 → not found
        coinQuery.enqueue([nil])
        // Call 2: input check for coin "99" → still on-chain, so revert
        coinQuery.enqueue([CoinSyncResult.OnChainCoin(value: 0, age: 0)])

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(coinService.savedCoins.isEmpty)
        #expect(coinService.markedSpentIds.isEmpty)
        #expect(coinService.markedAvailableIds == ["99"])
        #expect(voucherService.deletedIdentifiers.isEmpty)
    }

    // MARK: - Multi-group unload, one group's WAL survives

    @Test("Multi-group unload, one group survives while other is deleted")
    func multiGroupUnload() async throws {
        // Group A already deleted (not in fetchAll); only Group B survives
        let groupBEntry = makeWALEntry(
            inputVoucherIds: ["v1"],
            expectedCoinIndices: [200],
            checkpointBlock: .known(number: 15, hash: Data(repeating: 0x00, count: 32))
        )

        walStore.fetchAllResult = [groupBEntry]
        coinQuery.fetchCoinsResults = [CoinSyncResult.OnChainCoin(value: 5, age: 10)]

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [groupBEntry.id])

        #expect(coinService.savedCoins == [Coin(exponent: 5, derivationIndex: 200, age: 10)])
        #expect(voucherService.deletedIdentifiers == ["v1"])
    }

    // MARK: - No WAL entries

    @Test("No WAL entries completes without service calls")
    func noWALEntries() async throws {
        walStore.fetchAllResult = []

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds.isEmpty)

        #expect(coinService.savedCoins.isEmpty)
        #expect(coinService.markedSpentIds.isEmpty)
        #expect(coinService.markedAvailableIds.isEmpty)
        #expect(voucherService.deletedIdentifiers.isEmpty)
        #expect(coinQuery.fetchCoinsCallCount == 0)
    }

    // MARK: - WAL entry with empty expected indices is deleted without queries

    @Test("WAL entry with no expected indices is deleted without on-chain query")
    func emptyExpectedIndices() async throws {
        let walEntry = makeWALEntry(inputCoinIds: ["99"], expectedCoinIndices: [])

        walStore.fetchAllResult = [walEntry]

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        // Query should not be called since there are no expected indices
        #expect(coinQuery.fetchCoinsCallCount == 0)
        #expect(coinService.savedCoins.isEmpty)
        #expect(coinService.markedSpentIds.isEmpty)
    }

    // MARK: - Status stream emits idle, recovering, completed

    @Test("Status stream emits .idle, .recovering, then .completed")
    func statusStream() async throws {
        walStore.fetchAllResult = [makeWALEntry(inputCoinIds: ["99"])]
        coinQuery.fetchCoinsResults = [CoinSyncResult.OnChainCoin(value: 3, age: 0)]

        let service = makeService()

        // Collect until terminal state — deterministic, no arbitrary sleeps needed
        let collectorTask = Task<[RecoveryStatus], Error> {
            var collected: [RecoveryStatus] = []
            for try await status in service.statusStream {
                collected.append(status)
                if status == .completed { break }
                if case .failed = status { break }
            }
            return collected
        }

        // Yield to let collector subscribe and receive .idle before recover() changes state
        await Task.yield()

        await service.recover()

        let statusSequence = try await collectorTask.value
        #expect(statusSequence == [.idle, .recovering, .completed])
    }

    // MARK: - Extrinsic confirmed but no coins found on-chain

    @Test("Confirmed extrinsic but no coins found returns early without saving")
    func confirmedButNoCoinFound() async throws {
        let walEntry = makeWALEntry(inputCoinIds: ["99"], expectedCoinIndices: [100, 101])

        walStore.fetchAllResult = [walEntry]
        // Call 1: output probe for indices [100, 101] → not found on-chain
        coinQuery.enqueue([nil, nil])
        // Call 2: input check for coin "99" → also not on-chain (consumed), so mark spent
        coinQuery.enqueue([nil])

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(coinService.savedCoins.isEmpty, "No coins should be saved if none found on-chain")
        #expect(coinService.markedSpentIds == ["99"])
    }

    // MARK: - Revert entry with both coin and voucher inputs

    @Test("Never broadcast extrinsic with coins and vouchers reverts both")
    func revertWithCoinsAndVouchers() async throws {
        let walEntry = makeWALEntry(
            inputCoinIds: ["99", "98"],
            inputVoucherIds: ["1", "2"],
            checkpointBlock: .pending
        )

        walStore.fetchAllResult = [walEntry]
        voucherService.fetchAllResult = [
            makeVoucher(derivationIndex: 1),
            makeVoucher(exponent: 4, derivationIndex: 2, recyclerIndex: 1)
        ]

        // Call 1: output probe for index 100 → not found
        coinQuery.enqueue([nil])
        // Call 2: input check for coins ["99", "98"] → still on-chain, so revert
        coinQuery.enqueue([
            CoinSyncResult.OnChainCoin(value: 0, age: 0),
            CoinSyncResult.OnChainCoin(value: 0, age: 0)
        ])

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(Set(coinService.markedAvailableIds) == Set(["99", "98"]))

        // Vouchers should be restored to available state
        #expect(voucherService.savedVouchers.count == 2)
        #expect(voucherService.savedVouchers.allSatisfy { $0.localState == .available })
    }

    // MARK: - Partial on-chain results (some coins not found)

    @Test("Partial on-chain results saves only found coins")
    func partialOnChainResults() async throws {
        let walEntry = makeWALEntry(inputCoinIds: ["99"], expectedCoinIndices: [100, 101, 102])

        walStore.fetchAllResult = [walEntry]
        coinQuery.fetchCoinsResults = [
            CoinSyncResult.OnChainCoin(value: 3, age: 0),
            nil,
            CoinSyncResult.OnChainCoin(value: 3, age: 0)
        ]

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(coinService.savedCoins == [
            Coin(exponent: 3, derivationIndex: 100, age: 0),
            Coin(exponent: 3, derivationIndex: 102, age: 0)
        ], "Only found coins should be saved")
        #expect(coinService.markedSpentIds == ["99"])
    }

    // MARK: - Multiple WAL entries processed concurrently

    @Test("Multiple WAL entries are processed concurrently")
    func multipleWALEntries() async throws {
        let walEntry1 = makeWALEntry(inputCoinIds: ["99"])
        let walEntry2 = makeWALEntry(
            inputVoucherIds: ["v1"],
            expectedCoinIndices: [200],
            checkpointBlock: .known(number: 10, hash: Data(repeating: 0x00, count: 32))
        )

        walStore.fetchAllResult = [walEntry1, walEntry2]
        coinQuery.fetchCoinsResults = [
            CoinSyncResult.OnChainCoin(value: 3, age: 0),
            CoinSyncResult.OnChainCoin(value: 4, age: 5)
        ]

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(Set(deletedIds) == Set([walEntry1.id, walEntry2.id]))

        #expect(coinService.savedCoins.count == 2)
        #expect(coinService.markedSpentIds == ["99"])
        #expect(voucherService.deletedIdentifiers == ["v1"])
    }

    // MARK: - Recipient claimed output coins before recovery ran

    @Test("Unload confirmed but outputs claimed by recipient — inputs consumed, mark spent")
    func recipientClaimedOutputs() async throws {
        // Outputs are nil (recipient claimed them).
        // Inputs (vouchers 10, 11) are also gone from chain (consumed by extrinsic).
        let walEntry = makeWALEntry(
            inputVoucherIds: ["10", "11"],
            expectedCoinIndices: [200, 201]
        )

        walStore.fetchAllResult = [walEntry]
        // Output probe: both nil (recipient claimed them)
        coinQuery.enqueue([nil, nil])
        // Input voucher check: both nil (consumed by the extrinsic)
        voucherQuery.enqueue([nil, nil])

        await makeService().recover()

        // Inputs consumed → delete WAL; no coins saved (recipient already has them)
        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(coinService.savedCoins.isEmpty, "No coins to save — recipient already claimed them")
        #expect(coinService.markedSpentIds.isEmpty, "No coin inputs for unload operation")
        #expect(Set(voucherService.deletedIdentifiers) == Set(["10", "11"]))
        #expect(coinService.markedAvailableIds.isEmpty)
    }

    // MARK: - Voucher inputs still on-chain → revert (unload not confirmed)

    @Test("Unload not confirmed — voucher inputs still on-chain, revert to available")
    func unloadNotConfirmed_voucherInputsPresent() async throws {
        let walEntry = makeWALEntry(
            inputVoucherIds: ["10", "11"],
            expectedCoinIndices: [200, 201],
            checkpointBlock: .pending
        )

        walStore.fetchAllResult = [walEntry]
        voucherService.fetchAllResult = [
            makeVoucher(derivationIndex: 10),
            makeVoucher(derivationIndex: 11)
        ]

        // Output probe: nil (not confirmed)
        coinQuery.enqueue([nil, nil])
        // Input voucher check: still on-chain → revert
        voucherQuery.enqueue([
            VoucherOnChainInfo(exponent: 3, ringPosition: .suspended, isUnloaded: false),
            VoucherOnChainInfo(exponent: 3, ringPosition: .suspended, isUnloaded: false)
        ])

        await makeService().recover()

        // Vouchers still on-chain → revert to available
        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id])

        #expect(coinService.savedCoins.isEmpty)
        #expect(coinService.markedSpentIds.isEmpty)
        #expect(voucherService.savedVouchers.count == 2)
        #expect(voucherService.savedVouchers.allSatisfy { $0.localState == .available })
    }

    // MARK: - Within mortality window — entry left pending, no revert

    // MARK: - Exceeded mortality window — inputs reverted

    @Test("Outputs nil, inputs present, extrinsic past mortality window — inputs reverted")
    func exceededMortalityWindow_inputsReverted() async throws {
        // checkpointBlock=800, mortality=64 → expires at block 864
        // current block=1000 → 1000 > 864 → expired → revert
        let walEntry = makeWALEntry(
            inputCoinIds: ["99"],
            checkpointBlock: .known(number: 800, hash: Data(repeating: 0x00, count: 32)),
            mortality: 64
        )

        walStore.fetchAllResult = [walEntry]
        // Output probe: nil (not confirmed)
        coinQuery.enqueue([nil])
        // Input check for coin "99": still on-chain → not consumed, so fall through to expiry check
        coinQuery.enqueue([CoinSyncResult.OnChainCoin(value: 0, age: 0)])

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds == [walEntry.id], "Expired entry must be deleted")

        #expect(coinService.markedAvailableIds == ["99"])
        #expect(coinService.markedSpentIds.isEmpty)
        #expect(coinService.savedCoins.isEmpty)
    }

    // MARK: - Within mortality window — entry left pending, no revert

    @Test("Outputs nil, inputs present, extrinsic still within mortality — entry left pending")
    func withinMortalityWindow_noPendingRevert() async throws {
        // checkpointBlock=900, mortality=200 → expires at block 1100
        // current block=1000 → NOT yet expired → should NOT revert
        let walEntry = makeWALEntry(
            inputCoinIds: ["99"],
            checkpointBlock: .known(number: 900, hash: Data(repeating: 0x00, count: 32)),
            mortality: 200
        )

        walStore.fetchAllResult = [walEntry]
        // Outputs: nil
        coinQuery.enqueue([nil])
        // Input check for coin "99": still on-chain
        coinQuery.enqueue([CoinSyncResult.OnChainCoin(value: 0, age: 0)])

        // Mock emits block 1000 (< 900 + 200 = 1100 → not expired). Entry stays pending.
        // Stream terminates after the single emission; recover() returns with the entry unresolved.

        await makeService().recover()

        let deletedIds = await walStore.deletedIds
        #expect(deletedIds.isEmpty, "Entry must not be deleted while extrinsic is still live")

        #expect(coinService.markedAvailableIds.isEmpty)
        #expect(coinService.markedSpentIds.isEmpty)
        #expect(coinService.savedCoins.isEmpty)
    }
}

extension RecoveryStatus: Equatable {
    public static func == (lhs: RecoveryStatus, rhs: RecoveryStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.recovering, .recovering),
             (.completed, .completed):
            true
        case (.failed, .failed):
            true
        default:
            false
        }
    }
}
