import Foundation
@testable import polkadot_app

actor MockChainLivenessAnchorProvider: ChainLivenessAnchorProviding {
    private(set) var fetchAnchorCalls: [(target: ChainConnectionTarget, slotCount: Int)] = []
    private var anchorToReturn: ChainLivenessAnchor?
    private var errorToThrow: Error?
    private var isGateClosed = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var parkObservers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func setAnchor(_ anchor: ChainLivenessAnchor?) {
        anchorToReturn = anchor
    }

    func setError(_ error: Error?) {
        errorToThrow = error
    }

    /// Parks every subsequent fetch until `release()`, so a test can observe the provider while a
    /// probe is genuinely outstanding. Without this the mock answers immediately and the hold
    /// cannot be exercised at all — a test would only be racing the completion.
    func closeGate() {
        isGateClosed = true
    }

    func openGate() {
        isGateClosed = false
    }

    /// Resumes everything parked so far. Does not change whether new calls park.
    func release() {
        let resumed = waiters.values
        waiters = [:]
        resumed.forEach { $0.resume() }
    }

    /// Suspends until at least `count` fetches are parked at the gate.
    func waitForParkedFetches(_ count: Int) async {
        guard waiters.count < count else {
            return
        }

        await withCheckedContinuation { parkObservers.append((count: count, continuation: $0)) }
    }

    func fetchAnchor(
        for target: ChainConnectionTarget,
        slotCount: Int
    ) async throws -> ChainLivenessAnchor {
        fetchAnchorCalls.append((target: target, slotCount: slotCount))

        if isGateClosed {
            try await park()
        }

        if let error = errorToThrow {
            throw error
        }

        guard let anchor = anchorToReturn else {
            throw NSError(domain: "MockChainLivenessAnchorProvider", code: -1)
        }

        return anchor
    }
}

private extension MockChainLivenessAnchorProvider {
    /// A cancelled fetch leaves the gate, as a real request would, so the provider's timeout can
    /// end a parked probe.
    func park() async throws {
        let id = UUID()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }

                waiters[id] = continuation
                notifyParkObservers()
            }
        } onCancel: {
            Task { await self.unpark(id) }
        }

        try Task.checkCancellation()
    }

    func unpark(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }

    func notifyParkObservers() {
        let parkedCount = waiters.count
        let ready = parkObservers.filter { $0.count <= parkedCount }
        parkObservers.removeAll { $0.count <= parkedCount }
        ready.forEach { $0.continuation.resume() }
    }
}
