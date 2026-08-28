import Testing
import Foundation
import os
import Products
@testable import polkadot_app

private final class FakeWorker: ProductWorkerRunning, @unchecked Sendable {
    private let onDispose: @Sendable () -> Void
    init(onDispose: @escaping @Sendable () -> Void) { self.onDispose = onDispose }
    func dispose() async { onDispose() }
}

private final class FakeWorkerFactory: ProductWorkerFactory, @unchecked Sendable {
    private let counts = OSAllocatedUnfairLock(initialState: (started: 0, disposed: 0))
    private let startDelay: Duration

    init(startDelay: Duration = .zero) { self.startDelay = startDelay }

    func startWorker(productId _: ProductId) async throws -> ProductWorkerRunning {
        if startDelay > .zero {
            try? await Task.sleep(for: startDelay)
        }
        counts.withLock { $0.started += 1 }
        return FakeWorker { [counts] in counts.withLock { $0.disposed += 1 } }
    }

    var started: Int { counts.withLock { $0.started } }
    var disposed: Int { counts.withLock { $0.disposed } }
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () -> Bool
) async {
    let start = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - start > timeout {
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@Suite("ProductWorkerManager")
struct ProductWorkerManagerTests {
    @Test("first lock starts the worker, additional locks do not restart it")
    func startsOnceForConcurrentConsumers() async {
        let factory = FakeWorkerFactory()
        let manager = ProductWorkerManager(factory: factory)

        let chat = manager.lock(productId: "getcash")
        let spa = manager.lock(productId: "getcash")

        await waitUntil { factory.started == 1 }
        #expect(factory.started == 1)
        #expect(factory.disposed == 0)

        withExtendedLifetime((chat, spa)) {}
    }

    @Test("worker is disposed only after the last lock is released")
    func disposesOnLastUnlock() async {
        let factory = FakeWorkerFactory()
        let manager = ProductWorkerManager(factory: factory)

        let chat = manager.lock(productId: "getcash")
        let spa = manager.lock(productId: "getcash")
        await waitUntil { factory.started == 1 }

        chat.unlock()
        // One consumer left: still alive.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(factory.disposed == 0)

        spa.unlock()
        await waitUntil { factory.disposed == 1 }
        #expect(factory.disposed == 1)
    }

    @Test("token unlock is idempotent")
    func tokenUnlockIsIdempotent() async {
        let factory = FakeWorkerFactory()
        let manager = ProductWorkerManager(factory: factory)

        let a = manager.lock(productId: "getcash")
        let b = manager.lock(productId: "getcash")
        await waitUntil { factory.started == 1 }

        a.unlock()
        a.unlock() // second release must not drop b's reference
        try? await Task.sleep(for: .milliseconds(50))
        #expect(factory.disposed == 0)

        b.unlock()
        await waitUntil { factory.disposed == 1 }
        #expect(factory.disposed == 1)
    }

    @Test("dropping a token releases its lock")
    func deinitReleasesLock() async {
        let factory = FakeWorkerFactory()
        let manager = ProductWorkerManager(factory: factory)

        do {
            let token = manager.lock(productId: "getcash")
            await waitUntil { factory.started == 1 }
            _ = token
        }

        await waitUntil { factory.disposed == 1 }
        #expect(factory.disposed == 1)
    }

    @Test("churn after a real start never leaks a worker")
    func churnStaysBalanced() async {
        let factory = FakeWorkerFactory()
        let manager = ProductWorkerManager(factory: factory)

        // One guaranteed start/dispose up front, on a short chain, so the balance
        // check below is never vacuous. This mirrors the other tests' timing.
        let first = manager.lock(productId: "getcash")
        await waitUntil { factory.started == 1 }
        first.unlock()

        // Then churn the same product. Fast toggling may start nothing each cycle
        // (a start re-checks it is still wanted first); the invariant is only that
        // whatever started is also disposed, never left running.
        for _ in 0 ..< 8 {
            let token = manager.lock(productId: "getcash")
            token.unlock()
        }

        // Balance, not a count or a deadline: a generous window absorbs slow CI
        // schedulers without turning task latency into a failure.
        await waitUntil(timeout: .seconds(30)) {
            factory.started == factory.disposed
        }
        #expect(factory.started == factory.disposed)
        #expect(factory.started >= 1)
    }
}
