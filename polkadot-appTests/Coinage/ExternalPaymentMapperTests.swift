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

    @Test("round-trips the persisted spend scope and origin-scoped identity", arguments: [
        SpendScope.spendable, SpendScope.withConfirmation
    ])
    func roundTripsSpendScope(scope: SpendScope) async throws {
        let store = makeStore()
        let payment = ExternalPayment(
            origin: "getcash.dot",
            paymentId: "0xab",
            amountInPlanks: 1_500,
            destination: destination,
            spendScope: scope
        )

        try await store.save(payment: payment)
        let fetched = try #require(try await store.fetchPayment(byId: payment.id))

        #expect(fetched.spendScope == scope)
        #expect(fetched.settledInPlanks == 0)
        #expect(fetched.round == 0)
        #expect(fetched.id == "getcash.dot:0xab")
        #expect(fetched.origin == "getcash.dot")
        #expect(fetched.paymentId == "0xab")
        #expect(fetched.amountInPlanks == 1_500)
    }

    @Test("legacy rows without an origin prefix read back as spendable with the whole id as paymentId")
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

        #expect(fetched.spendScope == .spendable)
        #expect(fetched.paymentId == "6F1E4A0C-LEGACY")
    }

    @Test("re-saving a later round keeps the scope and persists settled value and round")
    func stageUpdateKeepsScope() async throws {
        let store = makeStore()
        var payment = ExternalPayment(
            origin: "getcash.dot",
            paymentId: "0xcd",
            amountInPlanks: 5,
            destination: destination,
            spendScope: .withConfirmation
        )
        try await store.save(payment: payment)

        payment.stage = .plan
        payment.settledInPlanks = 3
        payment.round = 1
        try await store.save(payment: payment)

        let fetched = try #require(try await store.fetchPayment(byId: payment.id))
        #expect(fetched.stage == .plan)
        #expect(fetched.spendScope == .withConfirmation)
        #expect(fetched.settledInPlanks == 3)
        #expect(fetched.round == 1)
    }
}
