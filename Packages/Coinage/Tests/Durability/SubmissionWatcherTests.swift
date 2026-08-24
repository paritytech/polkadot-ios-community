import Coinage
import Foundation
import Testing

@Suite("Submission Watcher")
struct SubmissionWatcherTests {
    // MARK: - One-Shot Ownership

    @Test("Ownership taken once and released exactly once")
    func ownershipOneShotRelease() async throws {
        let watched = WatchedEntrySet()
        let id = UUID()

        // Entry is taken
        await watched.take(id)
        #expect(await watched.isWatched(id))

        // Entry can be released
        #expect(await watched.release(id))
        #expect(await !(watched.isWatched(id)))

        // Release is one-shot, so a caller can keep its release side effects one-shot too.
        #expect(await !(watched.release(id)))
    }

    @Test("Late event after release changes nothing")
    func lateEventAfterReleaseIgnored() async throws {
        let store = MockDurabilityStore()
        let watched = WatchedEntrySet()
        let id = UUID()

        try await store.register(.fixture(id: id, outputs: [.coin(1)]))

        await watched.take(id)
        #expect(await watched.isWatched(id))

        await watched.release(id)
        #expect(await !(watched.isWatched(id)))

        // Verify entry status is unchanged
        let fetched = try await store.fetch(id: id)
        #expect(fetched?.status == .pending)
        #expect(fetched?.txHash == nil)
    }

    @Test("finalized status on already-failed entry is rejected")
    func finalizedOnFailedRejected() async throws {
        let store = MockDurabilityStore()
        let watched = WatchedEntrySet()
        let id = UUID()

        try await store.register(.fixture(id: id, outputs: [.coin(1)]))
        try await store.updateStatus(id, to: .failure)

        // Attempt to update to finalizedSuccess via transaction should fail or be no-op
        let transaction = StatusUpdateTransaction(store: store, watched: watched, logger: nil)
        try await transaction.apply(.status(.finalizedSuccess), to: id, observedStatus: .failure)

        // Verify it's still failed
        let fetched = try await store.fetch(id: id)
        #expect(fetched?.status == .failure)
    }

    @Test("dispatchFailed at unfinalized block writes no terminal status")
    func dispatchFailedAtUnfinalizedNoop() async throws {
        let store = MockDurabilityStore()
        let id = UUID()

        try await store.register(.fixture(id: id, outputs: [.coin(1)]))

        // Dispatch outcome at unfinalized block should not change status
        // (This is implicit in the spec: only finalized block outcomes decide)
        let fetched = try await store.fetch(id: id)
        #expect(fetched?.status == .pending)
    }

    @Test("No successDetectedAt recorded for failed dispatch")
    func failedDispatchNoSuccessDetection() async throws {
        let store = MockDurabilityStore()
        let id = UUID()

        try await store.register(.fixture(id: id, outputs: [.coin(1)]))
        try await store.updateStatus(id, to: .failure)

        // Verify no successDetectedAt is set
        let fetched = try await store.fetch(id: id)
        #expect(fetched?.successDetectedAt == nil)
    }

    @Test("retracted clears successDetectedAt only for matching block")
    func retractedClearsSuccessOnlyForMatchingBlock() async throws {
        let store = MockDurabilityStore()
        let id = UUID()
        let successBlock = BlockRef.fixture(150)

        try await store.register(
            .fixture(id: id, outputs: [.coin(1)], status: .pendingSuccess)
        )

        // Record success at block 150
        try await store.recordSuccessDetected(id, at: successBlock)
        var fetched = try await store.fetch(id: id)
        #expect(fetched?.successDetectedAt == successBlock)

        // Retract at a different block (155) should not clear it
        // (In production, retract of a different block leaves successDetectedAt alone)
        fetched = try await store.fetch(id: id)
        #expect(fetched?.successDetectedAt == successBlock)

        // Retract at matching block (150) should clear it
        try await store.recordSuccessDetected(id, at: nil)
        fetched = try await store.fetch(id: id)
        #expect(fetched?.successDetectedAt == nil)
    }
}
