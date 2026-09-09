import Testing
import Foundation
import AsyncExtensions
@testable import Coinage

struct IncomingPaymentContextTests {
    @Test func processSeedsDetecting() async throws {
        let context = IncomingPaymentContext(store: InMemoryIncomingPaymentStore(), logger: StubLogger())

        // A run that reports nothing — the subject should still be seeded `.detecting`.
        await context.process(groupId: "g1") { Task {} }

        let stream = try #require(await context.liveStatusStream(for: "g1"))
        for try await status in stream {
            #expect(status == .detecting)
            break
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func terminalStatusMarksProcessed() async throws {
        let store = InMemoryIncomingPaymentStore()
        let context = IncomingPaymentContext(store: store, logger: StubLogger())

        await context.process(groupId: "g1") {
            Task {
                await context.report(.claiming, for: "g1")
                await context.report(.claimed(finalized: true), for: "g1")
            }
        }

        let stream = try #require(await context.liveStatusStream(for: "g1"))
        var last: IncomingPaymentStatus?
        for try await status in stream {
            last = status
            if status.isTerminal { break }
        }
        #expect(last == .claimed(finalized: true))

        // `report` persists after emitting; give the trailing `markProcessed` a moment.
        try await waitUntil { store.processedGroupIds() == ["g1"] }
        #expect(store.processedGroupIds() == ["g1"])
    }

    @Test func nonTerminalStatusDoesNotMarkProcessed() async throws {
        let store = InMemoryIncomingPaymentStore()
        let context = IncomingPaymentContext(store: store, logger: StubLogger())

        await context.process(groupId: "g1") {
            Task { await context.report(.claiming, for: "g1") }
        }

        let stream = try #require(await context.liveStatusStream(for: "g1"))
        for try await status in stream where status == .claiming {
            break
        }
        #expect(store.processedGroupIds().isEmpty)
    }

    @Test func seededStatusStreamReplaysValue() async throws {
        let context = IncomingPaymentContext(store: InMemoryIncomingPaymentStore(), logger: StubLogger())

        let stream = await context.seededStatusStream(.notClaimed, for: "g1")
        for try await status in stream {
            #expect(status == .notClaimed)
            break
        }
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: Duration = .seconds(3)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
