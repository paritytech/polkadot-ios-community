import AsyncExtensions
import Foundation
import os
@testable import Coinage

/// In-memory `ExternalPaymentStoring`. Every save republishes the whole table so the observe
/// streams behave like `subscribeSnapshot` / `subscribeSingle`: current value first, then updates.
final class InMemoryExternalPaymentStore: ExternalPaymentStoring, @unchecked Sendable {
    struct Failure: Error {}

    private let payments = OSAllocatedUnfairLock(initialState: [String: ExternalPayment]())
    private let subject = AsyncCurrentValueSubject<[ExternalPayment]>([])

    var saveError: Error?

    init(seed: [ExternalPayment] = []) {
        payments.withLock { table in
            for payment in seed {
                table[payment.id] = payment
            }
        }
        publish()
    }

    func save(payment: ExternalPayment) async throws {
        if let saveError { throw saveError }
        payments.withLock { $0[payment.id] = payment }
        publish()
    }

    func fetchPayment(byId id: String) async throws -> ExternalPayment? {
        payments.withLock { $0[id] }
    }

    func observePayment(id: String) -> AnyAsyncSequence<ExternalPayment?> {
        subject
            .map { $0.first { $0.id == id } }
            .eraseToAnyAsyncSequence()
    }

    func observeNonTerminalPayments() -> AnyAsyncSequence<[ExternalPayment]> {
        subject
            .map { $0.filter { !$0.stage.isTerminal } }
            .eraseToAnyAsyncSequence()
    }

    // MARK: - Test inspection

    func payment(id: String) -> ExternalPayment? {
        payments.withLock { $0[id] }
    }

    func all() -> [ExternalPayment] {
        payments.withLock { Array($0.values) }
    }

    private func publish() {
        subject.send(all().sorted { $0.createdAt < $1.createdAt })
    }
}
