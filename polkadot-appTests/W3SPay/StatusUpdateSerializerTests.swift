import Testing

@testable import polkadot_app

@Suite("StatusUpdateSerializer concurrency guarantees")
struct StatusUpdateSerializerTests {
    @Test("Work items execute serially with no overlap")
    func noOverlapBetweenWorkItems() async throws {
        let serializer = StatusUpdateSerializer()
        let accumulator = Accumulator()

        // Launch N concurrent calls; each increments active, checks maxActive, yields, decrements
        let N = 50
        let tasks = (0 ..< N).map { _ in
            Task {
                try await serializer.run {
                    let count = await accumulator.incrementActive()
                    // Record the max if needed
                    _ = await accumulator.recordMaxActive(count)

                    // Suspend with Task.yield() to allow potential reentrancy
                    // (but the serializer prevents it)
                    await Task.yield()

                    await accumulator.decrementActive()
                }
            }
        }

        // Wait for all tasks
        for task in tasks {
            try await task.value
        }

        // Verify: maxActive should be 1 (no overlap) and completedCount should be N
        let maxActive = await accumulator.getMaxActive()
        let completedCount = await accumulator.getCompletedCount()

        #expect(maxActive == 1, "Max concurrent work items should be 1, got \(maxActive)")
        #expect(completedCount == N, "Should complete all \(N) work items, got \(completedCount)")
    }

    @Test("Error in one work item does not break the chain for subsequent items")
    func errorIsolation() async throws {
        let serializer = StatusUpdateSerializer()
        let recorder = OrderRecorder()

        enum TestError: Error {
            case expectedFailure
        }

        // First work item throws
        let task1 = Task {
            await #expect(throws: TestError.self) {
                try await serializer.run {
                    await recorder.append(1)
                    throw TestError.expectedFailure
                }
            }
        }

        await task1.value

        // Second work item should still execute (chain not broken)
        let task2 = Task {
            try await serializer.run {
                await recorder.append(2)
            }
        }

        try await task2.value

        // Third work item should also execute
        let task3 = Task {
            try await serializer.run {
                await recorder.append(3)
            }
        }

        try await task3.value

        // All three should have been recorded despite the error in task1
        let recorded = await recorder.getOrder()
        #expect(recorded == [1, 2, 3], "All work items should execute despite error in first one")
    }
}

// MARK: - Test Helpers

/// Actor to safely track active work items and max concurrency
private actor Accumulator {
    private var active: Int = 0
    private var maxActive: Int = 0
    private var completedCount: Int = 0

    func incrementActive() -> Int {
        active += 1
        maxActive = max(maxActive, active)
        return active
    }

    func decrementActive() {
        active -= 1
        completedCount += 1
    }

    func recordMaxActive(_ current: Int) {
        maxActive = max(maxActive, current)
    }

    func getMaxActive() -> Int {
        maxActive
    }

    func getCompletedCount() -> Int {
        completedCount
    }
}

/// Actor to record execution order of work items
private actor OrderRecorder {
    private var order: [Int] = []

    func append(_ index: Int) {
        order.append(index)
    }

    func getOrder() -> [Int] {
        order
    }
}
