import Foundation
import Products
import StructuredConcurrency
import SubstrateSdk

// MARK: - Signing

extension ProductsNativeApi {
    func signPayload(_ payload: SignTransactionPayload) async throws -> SignResult {
        let signingRequest = PolkadotHostRemoteMessage.SigningRequest.transaction(payload)
        let model: PolkadotHostSigningModel = .signingRequest(signingRequest)

        let context = ProductSigningContext(
            requesterName: productId,
            signingModel: model
        )

        logger.debug("Proceeding with signing payload")

        return try await withCheckedThrowingContinuation { continuation in
            context.setSignResultContinuation(continuation)
            Task {
                do {
                    try await self.signingHandler.sponsorAndPresent(
                        model: model,
                        context: context
                    )
                } catch {
                    logger.error("Sign payload failed: \(error)")
                    try? await context.rejectRequest()
                }
            }
        }
    }

    func signRaw(_ payload: SigningRawPayload) async throws -> SignResult {
        let rawPayload = payload.toHostSigningRawPayload()

        let signingRequest = PolkadotHostRemoteMessage.SigningRequest.rawPayload(rawPayload)
        let model: PolkadotHostSigningModel = .signingRequest(signingRequest)

        let context = ProductSigningContext(
            requesterName: productId,
            signingModel: model
        )

        logger.debug("Proceeding with signing raw data")

        return try await withCheckedThrowingContinuation { continuation in
            context.setSignResultContinuation(continuation)
            Task {
                do {
                    try await self.signingHandler.sponsorAndPresent(
                        model: model,
                        context: context
                    )
                } catch {
                    logger.error("Sign raw failed: \(error)")
                    try? await context.rejectRequest()
                }
            }
        }
    }

    func createTransaction(
        _ payload: CreateTransactionPayload<ProductAccountId>
    ) async throws -> CreateTransactionResult {
        let model: PolkadotHostSigningModel = .createTransaction(payload)

        let context = ProductSigningContext(
            requesterName: productId,
            signingModel: model
        )

        logger.debug("Proceeding with creating transaction")

        return try await withCheckedThrowingContinuation { continuation in
            context.setCreateTransactionContinuation(continuation)
            Task {
                do {
                    try await self.signingHandler.sponsorAndPresent(
                        model: model,
                        context: context
                    )
                } catch {
                    logger.error("Create transaction failed: \(error)")
                    try? await context.rejectRequest()
                }
            }
        }
    }
}
