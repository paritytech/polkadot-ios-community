import AsyncExtensions
import Foundation
import os
@testable import Coinage

/// In-memory `IncomingPaymentStoring` for tests. Thread-safe; publishes active-payment snapshots so
/// `setup()` resume can be exercised. `saveError`/`fetchError` inject failures.
final class InMemoryIncomingPaymentStore: IncomingPaymentStoring, @unchecked Sendable {
    struct Failure: Error {}

    private struct State {
        var payments: [CoinageTxGroupId: IncomingPayment] = [:]
        var processedGroupIds: [CoinageTxGroupId] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let activeSubject = AsyncCurrentValueSubject<[IncomingPayment]>([])

    var saveError: Error?
    var fetchError: Error?

    init(seed: [IncomingPayment] = []) {
        state.withLock { state in
            for payment in seed {
                state.payments[payment.groupId] = payment
            }
        }
        publishActive()
    }

    func save(_ payment: IncomingPayment) async throws {
        if let saveError { throw saveError }
        state.withLock { $0.payments[payment.groupId] = payment }
        publishActive()
    }

    func fetch(groupId: CoinageTxGroupId) async throws -> IncomingPayment? {
        if let fetchError { throw fetchError }
        return state.withLock { $0.payments[groupId] }
    }

    func fetchActivePayments() async throws -> [IncomingPayment] {
        state.withLock { Array($0.payments.values.filter { !$0.processed }) }
    }

    func markProcessed(groupId: CoinageTxGroupId) async throws {
        state.withLock { state in
            state.processedGroupIds.append(groupId)
            if let existing = state.payments[groupId] {
                state.payments[groupId] = IncomingPayment(
                    paymentId: existing.paymentId,
                    productId: existing.productId,
                    source: existing.source,
                    amount: existing.amount,
                    processed: true,
                    createdAt: existing.createdAt
                )
            }
        }
        publishActive()
    }

    func observePayment(groupId: CoinageTxGroupId) -> AnyAsyncSequence<IncomingPayment?> {
        let current = state.withLock { $0.payments[groupId] }
        return AsyncStream<IncomingPayment?> { continuation in
            continuation.yield(current)
            continuation.finish()
        }.eraseToAnyAsyncSequence()
    }

    func observeActivePayments() -> AnyAsyncSequence<[IncomingPayment]> {
        activeSubject.eraseToAnyAsyncSequence()
    }

    // MARK: - Test inspection

    func processedGroupIds() -> [CoinageTxGroupId] {
        state.withLock { $0.processedGroupIds }
    }

    func payment(for groupId: CoinageTxGroupId) -> IncomingPayment? {
        state.withLock { $0.payments[groupId] }
    }

    private func publishActive() {
        let active = state.withLock { Array($0.payments.values.filter { !$0.processed }) }
        activeSubject.send(active)
    }
}
