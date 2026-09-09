import Testing
import Foundation
import BigInt
import SubstrateSdk
@testable import Coinage

struct IncomingPaymentModelTests {
    @Test func groupIdBindsProductAndPayment() {
        #expect(IncomingPayment.groupId(productId: "prodA", paymentId: "pay1") == "prodA:pay1")

        let payment = IncomingPayment(
            paymentId: "pay1",
            productId: "prodA",
            source: .coinsFromPrivateKeys(secretKeys: []),
            amount: 0,
            processed: false,
            createdAt: Date()
        )
        #expect(payment.groupId == "prodA:pay1")
    }

    @Test func isActiveReflectsProcessed() {
        func make(processed: Bool) -> IncomingPayment {
            IncomingPayment(
                paymentId: "p",
                productId: "prod",
                source: .coinsFromPrivateKeys(secretKeys: []),
                amount: 0,
                processed: processed,
                createdAt: Date()
            )
        }
        #expect(make(processed: false).isActive)
        #expect(!make(processed: true).isActive)
    }

    @Test func sourceExposesTypeAndSecretKeys() {
        let coins = IncomingPaymentSource.coinsFromPrivateKeys(secretKeys: [Data([1]), Data([2])])
        #expect(coins.sourceType == .coins)
        #expect(coins.secretKeys == [Data([1]), Data([2])])

        let asset = IncomingPaymentSource.externalAssetFromWallet(secretKey: Data([9]))
        #expect(asset.sourceType == .externalAsset)
        #expect(asset.secretKeys == [Data([9])])
    }

    @Test func sourceReconstructsFromTypeAndKeys() throws {
        let asset = try IncomingPaymentSource(sourceType: .externalAsset, secretKeys: [Data([9])])
        #expect(asset == .externalAssetFromWallet(secretKey: Data([9])))

        let coins = try IncomingPaymentSource(sourceType: .coins, secretKeys: [Data([1]), Data([2])])
        #expect(coins == .coinsFromPrivateKeys(secretKeys: [Data([1]), Data([2])]))
    }

    @Test func externalAssetReconstructionRequiresAKey() {
        #expect(throws: (any Error).self) {
            _ = try IncomingPaymentSource(sourceType: .externalAsset, secretKeys: [])
        }
    }

    @Test func onlyFinalizedClaimedAndPartialAndNotClaimedAreTerminal() {
        #expect(!IncomingPaymentStatus.detecting.isTerminal)
        #expect(!IncomingPaymentStatus.claiming.isTerminal)
        #expect(!IncomingPaymentStatus.claimed(finalized: false).isTerminal)
        #expect(IncomingPaymentStatus.claimed(finalized: true).isTerminal)
        #expect(IncomingPaymentStatus.claimedPartially(actualClaimed: 5).isTerminal)
        #expect(IncomingPaymentStatus.notClaimed.isTerminal)
    }

    @Test func statusMapsFromDetection() {
        #expect(IncomingPaymentStatus(detection: .detecting) == .detecting)
        #expect(IncomingPaymentStatus(detection: .claiming) == .claiming)
        // `claimingRest` is still in progress → reported as claiming.
        #expect(IncomingPaymentStatus(detection: .claimingRest(claimed: 3)) == .claiming)
        #expect(IncomingPaymentStatus(detection: .claimed(amount: 10, finalized: true)) == .claimed(finalized: true))
        #expect(IncomingPaymentStatus(detection: .claimed(amount: 10, finalized: false)) == .claimed(finalized: false))
        #expect(IncomingPaymentStatus(detection: .claimedPartially(claimed: 4)) == .claimedPartially(actualClaimed: 4))
        #expect(IncomingPaymentStatus(detection: .notClaimed) == .notClaimed)
    }
}
