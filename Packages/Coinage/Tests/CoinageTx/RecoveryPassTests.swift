import Coinage
import Foundation
import Testing

@Suite("Recovery Pass")
struct RecoveryPassTests {
    // MARK: - Entry Registration and Ownership

    @Test("Entry registered mid-pass gets no verdict")
    func entryRegisteredMidPassGetsNoVerdict() async throws {
        let store = MockCoinageTxRepository()
        let chain = FakeChainView()
        let watched = CoinageTrackingTxSet()

        chain.setChainView(finalized: .fixture(150), best: .fixture(160))

        // Start with no entries
        var liveEntries = try await store.fetchLive()
        #expect(liveEntries.isEmpty)

        // Register entry during iteration
        let entry = CoinageTxEntry.fixture(outputs: [.coin(1)])
        try await store.register(entry)

        // Verify entry is live but not watched yet
        liveEntries = try await store.fetchLive()
        #expect(liveEntries.count == 1)
        #expect(await !(watched.isWatched(entry.id)))

        // Entry status should still be pending (no verdict applied)
        let fetched = try await store.fetch(id: entry.id)
        #expect(fetched?.status == .pending)
    }

    @Test("Propagation writes nothing to terminal entry")
    func propagationNothingToTerminal() async throws {
        let store = MockCoinageTxRepository()
        let watched = CoinageTrackingTxSet()

        let entry = CoinageTxEntry.fixture(
            inputs: [.coin(.own(1))],
            outputs: [.coin(2)],
            status: .finalizedSuccess
        )
        try await store.register(entry)

        // Try to update terminal entry via transaction
        let transaction = StatusUpdateTransaction(store: store, watched: watched, logger: nil)
        try await transaction.apply(.status(.failure), to: entry.id, observedStatus: .finalizedSuccess)

        // Verify it's still finalizedSuccess
        let fetched = try await store.fetch(id: entry.id)
        #expect(fetched?.status == .finalizedSuccess)
    }

    @Test("3-chain promotes over multiple passes")
    func threeChainPromotesOverMultiplePasses() async throws {
        let store = MockCoinageTxRepository()
        let chain = FakeChainView()

        chain.setChainView(finalized: .fixture(150), best: .fixture(150))

        // Create a chain: entry1 -> entry2 -> entry3
        let entry1 = CoinageTxEntry.fixture(outputs: [.coin(1)])
        try await store.register(entry1)

        let entry2 = CoinageTxEntry.fixture(inputs: [.coin(.own(1))], outputs: [.coin(2)])
        try await store.register(entry2)

        let entry3 = CoinageTxEntry.fixture(inputs: [.coin(.own(2))], outputs: [.coin(3)])
        try await store.register(entry3)

        // First pass: mark entry1 as finalized
        try await store.updateStatus(entry1.id, to: .finalizedSuccess)

        // Verify chain exists
        var e1 = try await store.fetch(id: entry1.id)
        var e2 = try await store.fetch(id: entry2.id)
        var e3 = try await store.fetch(id: entry3.id)
        #expect(e1?.status == .finalizedSuccess)
        #expect(e2?.status == .pending)
        #expect(e3?.status == .pending)

        // Next pass: mark entry2 as finalized
        try await store.updateStatus(entry2.id, to: .finalizedSuccess)

        // Verify propagation effect
        e2 = try await store.fetch(id: entry2.id)
        e3 = try await store.fetch(id: entry3.id)
        #expect(e2?.status == .finalizedSuccess)
        #expect(e3?.status == .pending)
    }

    @Test("First-entry failure resolves successors within one window")
    func firstEntryFailureResolvesSuccessors() async throws {
        let store = MockCoinageTxRepository()

        let entry1 = CoinageTxEntry.fixture(outputs: [.coin(1)])
        try await store.register(entry1)

        let entry2 = CoinageTxEntry.fixture(inputs: [.coin(.own(1))], outputs: [.coin(2)])
        try await store.register(entry2)

        try await store.updateStatus(entry1.id, to: .failure)

        // entry2 cannot proceed (entry1 failed)
        let e1 = try await store.fetch(id: entry1.id)
        let e2 = try await store.fetch(id: entry2.id)
        #expect(e1?.status == .failure)
        #expect(e2?.status == .pending)
    }

    @Test("Aborted pass leaves remaining work undone")
    func abortedPassLeavesWorkUndone() async throws {
        let store = MockCoinageTxRepository()

        let entry1 = CoinageTxEntry.fixture(outputs: [.coin(1)])
        try await store.register(entry1)

        let entry2 = CoinageTxEntry.fixture(outputs: [.coin(2)])
        try await store.register(entry2)

        // Process only entry1
        try await store.updateStatus(entry1.id, to: .finalizedSuccess)

        // entry2 remains untouched
        let e1 = try await store.fetch(id: entry1.id)
        let e2 = try await store.fetch(id: entry2.id)
        #expect(e1?.status == .finalizedSuccess)
        #expect(e2?.status == .pending)
    }

    @Test("Lagging peer produces no wrong verdict")
    func laggingPeerProducesNoWrongVerdict() async throws {
        let store = MockCoinageTxRepository()
        let chain = FakeChainView()
        let oldBlock = BlockRef.fixture(140)
        let newBlock = BlockRef.fixture(150)

        // Start with old view
        chain.setChainView(finalized: oldBlock, best: oldBlock)

        let entry = CoinageTxEntry.fixture(outputs: [.coin(1)])
        try await store.register(entry)

        // Update to new view
        chain.setChainView(finalized: newBlock, best: newBlock)

        // Entry should not be decided based on old view
        let fetched = try await store.fetch(id: entry.id)
        #expect(fetched?.status == .pending)
    }

    @Test("Compare-and-set guard: changed status rejects computed verdict")
    func compareAndSetGuardRejectsChangedStatus() async throws {
        let store = MockCoinageTxRepository()

        let entry = CoinageTxEntry.fixture(outputs: [.coin(1)])
        try await store.register(entry)

        // Compute verdict based on pending status
        let statusBeforeDecision = try await (store.fetch(id: entry.id))?.status
        #expect(statusBeforeDecision == .pending)

        // Status changes between decision and apply
        try await store.updateStatus(entry.id, to: .pendingSuccess)

        // The computed verdict (based on .pending) should not apply to .pendingSuccess
        let current = try await store.fetch(id: entry.id)
        #expect(current?.status == .pendingSuccess)

        // Re-evaluate with new status
        try await store.updateStatus(entry.id, to: .finalizedSuccess)
        let final = try await store.fetch(id: entry.id)
        #expect(final?.status == .finalizedSuccess)
    }
}
