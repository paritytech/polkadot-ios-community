import Testing
import Foundation
import NovaCrypto
import SubstrateSdk
@testable import Coinage

struct IncomingPaymentServiceTests {
    private let keyFactory = SNKeyFactory()

    private func validSecret(_ seedByte: UInt8) throws -> Data {
        try keyFactory.createKeypair(fromSeed: Data(repeating: seedByte, count: 32)).privateKey().rawData()
    }

    private func makeService(store: InMemoryIncomingPaymentStore) -> IncomingPaymentService {
        IncomingPaymentService(
            store: store,
            validator: IncomingPaymentSourceValidator(),
            paymentContext: IncomingPaymentContext(store: store, logger: StubLogger()),
            claimCoinsService: StubClaimCoinsService(),
            claimAssetService: StubClaimAssetService(),
            txService: StubCoinageTxServicing(),
            contextProvider: StubDenominationContextProvider(),
            instanceId: 0,
            logger: StubLogger()
        )
    }

    @Test func acceptPersistsNewPayment() async throws {
        let store = InMemoryIncomingPaymentStore()
        let service = makeService(store: store)

        try await service.accept(
            amount: 100,
            source: .coinsFromPrivateKeys(secretKeys: [validSecret(0x01)]),
            paymentId: "p1",
            productId: "prod"
        )

        let saved = try #require(store.payment(for: "prod:p1"))
        #expect(saved.amount == 100)
        #expect(saved.processed == false)
        #expect(saved.groupId == "prod:p1")
    }

    @Test func acceptRejectsDuplicateGroupId() async throws {
        let key = try validSecret(0x01)
        let existing = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            source: .coinsFromPrivateKeys(secretKeys: [key]),
            amount: 100,
            processed: false,
            createdAt: Date()
        )
        let store = InMemoryIncomingPaymentStore(seed: [existing])
        let service = makeService(store: store)

        await #expect {
            try await service.accept(
                amount: 100,
                source: .coinsFromPrivateKeys(secretKeys: [key]),
                paymentId: "p1",
                productId: "prod"
            )
        } throws: { ($0 as? IncomingPaymentError) == .alreadyExists }
    }

    @Test func sameProductPaymentIdAcrossProductsDoesNotCollide() async throws {
        let key = try validSecret(0x02)
        let existing = IncomingPayment(
            paymentId: "shared",
            productId: "prodA",
            source: .coinsFromPrivateKeys(secretKeys: [key]),
            amount: 10,
            processed: false,
            createdAt: Date()
        )
        let store = InMemoryIncomingPaymentStore(seed: [existing])
        let service = makeService(store: store)

        // Same paymentId, different product, different source → distinct operation.
        try await service.accept(
            amount: 20,
            source: .coinsFromPrivateKeys(secretKeys: [validSecret(0x03)]),
            paymentId: "shared",
            productId: "prodB"
        )

        #expect(store.payment(for: "prodB:shared") != nil)
        #expect(store.payment(for: "prodA:shared") != nil)
    }

    @Test func acceptRejectsBusySource() async throws {
        let key = try validSecret(0x05)
        let active = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            source: .coinsFromPrivateKeys(secretKeys: [key]),
            amount: 100,
            processed: false,
            createdAt: Date()
        )
        let store = InMemoryIncomingPaymentStore(seed: [active])
        let service = makeService(store: store)

        await #expect {
            try await service.accept(
                amount: 50,
                source: .coinsFromPrivateKeys(secretKeys: [key]),
                paymentId: "p2",
                productId: "prod"
            )
        } throws: { ($0 as? IncomingPaymentError) == .sourceBusy }
    }

    @Test func processedSourceIsNotBusy() async throws {
        let key = try validSecret(0x06)
        let done = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            source: .coinsFromPrivateKeys(secretKeys: [key]),
            amount: 100,
            processed: true,
            createdAt: Date()
        )
        let store = InMemoryIncomingPaymentStore(seed: [done])
        let service = makeService(store: store)

        // Reusing a source whose only prior payment is terminal is allowed.
        try await service.accept(
            amount: 50,
            source: .coinsFromPrivateKeys(secretKeys: [key]),
            paymentId: "p2",
            productId: "prod"
        )
        #expect(store.payment(for: "prod:p2") != nil)
    }

    @Test func acceptRejectsInvalidSource() async throws {
        let store = InMemoryIncomingPaymentStore()
        let service = makeService(store: store)

        await #expect {
            try await service.accept(
                amount: 10,
                source: .coinsFromPrivateKeys(secretKeys: [Data(repeating: 0, count: 32)]),
                paymentId: "p1",
                productId: "prod"
            )
        } throws: { Self.isInvalidSource($0) }
    }

    @Test func acceptMapsUnexpectedFailureToUnknown() async throws {
        let store = InMemoryIncomingPaymentStore()
        store.fetchError = InMemoryIncomingPaymentStore.Failure()
        let service = makeService(store: store)

        await #expect {
            try await service.accept(
                amount: 10,
                source: .coinsFromPrivateKeys(secretKeys: [validSecret(0x07)]),
                paymentId: "p1",
                productId: "prod"
            )
        } throws: { Self.isUnknown($0) }
    }

    private static func isInvalidSource(_ error: any Error) -> Bool {
        guard let error = error as? IncomingPaymentError, case .invalidSource = error else { return false }
        return true
    }

    private static func isUnknown(_ error: any Error) -> Bool {
        guard let error = error as? IncomingPaymentError, case .unknown = error else { return false }
        return true
    }
}
