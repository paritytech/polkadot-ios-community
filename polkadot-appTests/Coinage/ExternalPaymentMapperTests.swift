import Foundation
import Testing
import Coinage
@testable import polkadot_app

@Suite("ExternalPaymentMapper")
struct ExternalPaymentMapperTests {
    private let destination = Data(repeating: 9, count: 32)

    private func makeStore() -> ExternalPaymentCoreDataStore {
        ExternalPaymentCoreDataStore(storageFacade: UserDataStorageTestFacade())
    }

    @Test("round-trips the origin-scoped identity and settled value")
    func roundTripsIdentityAndSettledValue() async throws {
        let store = makeStore()
        var payment = ExternalPayment(
            origin: "getcash.dot",
            paymentId: "0xab",
            amountInPlanks: 1_500,
            destination: destination
        )
        try await store.save(payment: payment)

        payment.stage = .partiallyCompleted
        payment.settledInPlanks = 1_000
        try await store.save(payment: payment)

        let fetched = try #require(try await store.fetchPayment(byId: payment.id))
        #expect(fetched.id == "getcash.dot:0xab")
        #expect(fetched.origin == "getcash.dot")
        #expect(fetched.paymentId == "0xab")
        #expect(fetched.amountInPlanks == 1_500)
        #expect(fetched.stage == .partiallyCompleted)
        #expect(fetched.settledInPlanks == 1_000)
    }

    @Test("legacy rows without an origin prefix read the whole id as paymentId with nothing settled")
    func legacyRowDefaults() async throws {
        let store = makeStore()
        let legacy = ExternalPayment(
            id: "6F1E4A0C-LEGACY",
            origin: "5Recipient",
            amountInPlanks: 10,
            destination: destination
        )

        try await store.save(payment: legacy)
        let fetched = try #require(try await store.fetchPayment(byId: legacy.id))

        #expect(fetched.paymentId == "6F1E4A0C-LEGACY")
        #expect(fetched.settledInPlanks == 0)
    }

    @Test("a legacy rescheduled row reads back as rescheduled so the service can resume it as plan")
    func legacyRescheduledRowIsPreserved() async throws {
        let store = makeStore()
        let legacy = ExternalPayment(
            origin: "getcash.dot",
            paymentId: "0xcd",
            amountInPlanks: 5,
            destination: destination,
            stage: .rescheduled
        )

        try await store.save(payment: legacy)
        let fetched = try #require(try await store.fetchPayment(byId: legacy.id))

        #expect(fetched.stage == .rescheduled)
    }
}
