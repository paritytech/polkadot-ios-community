import BigInt
import Foundation
import Coinage
import KeyDerivation
import Products
import SubstrateSdk
import AsyncExtensions
import StructuredConcurrency

// MARK: - Payments

extension ProductsNativeApi {
    func subscribePaymentBalance() async throws -> AnyAsyncSequence<PaymentBalance> {
        guard
            try await permissionGuard.consumePermission(
                productId: productId,
                permission: .balanceAccess
            ) else {
            throw ProductNativeApiError.permissionDenied
        }

        let coinageService = try requirePaymentsSupport().coinageService
        let balanceService = try await coinageService.coinageBalanceService()
        return balanceService.balanceStream
            .map { balance in
                PaymentBalance(available: balance.availablePrivate)
            }
            .eraseToAnyAsyncSequence()
    }

    func requestPayment(amountInPlanks: String, destination: AccountId) async throws -> PaymentReceipt {
        guard let amount = BigUInt(amountInPlanks) else {
            throw ProductNativeApiError.invalidParam("amountInPlanks")
        }

        let externalPaymentService = try requirePaymentsSupport().externalPaymentService

        try await checkSufficientBalance(amount: amount)
        try await awaitUserApproval(amount: amount, destination: destination)

        let paymentId = try await externalPaymentService.initiatePayment(
            origin: productId,
            amountInPlanks: amount,
            destination: destination
        )

        return PaymentReceipt(paymentId: paymentId)
    }

    func subscribePaymentStatus(paymentId: String) async throws -> AnyAsyncSequence<HostPaymentStatus> {
        let externalPaymentService = try requirePaymentsSupport().externalPaymentService
        return try externalPaymentService.subscribePaymentStatus(paymentId: paymentId)
            .map { status in
                switch status {
                case .processing: .processing
                case .completed: .completed
                case let .failed(reason): .failed(reason: reason)
                }
            }
            .eraseToAnyAsyncSequence()
    }

    /// Registers an idempotent top-up bound to `(productId, id)` and returns once initialization has
    /// concluded. The claim is driven by `IncomingPaymentService`; the product observes progress via
    /// ``subscribePaymentTopUpStatus(id:)``.
    func paymentTopUp(amount: Balance, source: PaymentTopUpSource, id: PaymentTopUpId) async throws {
        let incomingPaymentService = try requirePaymentsSupport().incomingPaymentService

        let descriptor: IncomingPaymentSourceDescriptor
        do {
            descriptor = try Self.incomingPaymentDescriptor(from: source, productId: productId)
        } catch {
            logger.error("Top-up source could not be described: \(error)")
            throw HostPaymentTopUpError.invalidSource
        }

        do {
            try await incomingPaymentService.accept(
                amount: amount,
                descriptor: descriptor,
                paymentId: id.toHex(),
                productId: productId
            )
        } catch {
            logger.error("Top-up could not be registered: \(error)")
            throw HostPaymentTopUpError(error, unknownReason: Self.topUpRegistrationFailed)
        }
    }

    func subscribePaymentTopUpStatus(
        id: PaymentTopUpId
    ) async throws -> AnyAsyncSequence<HostPaymentTopUpStatus> {
        do {
            let incomingPaymentService = try requirePaymentsSupport().incomingPaymentService

            return try await incomingPaymentService.subscribeStatus(
                for: id.toHex(),
                productId: productId
            )
            .map { HostPaymentTopUpStatus(status: $0) }
            .eraseToAnyAsyncSequence()
        } catch {
            logger.error("Top-up status could not be observed: \(error)")
            throw HostPaymentTopUpError(error, unknownReason: Self.topUpStatusUnavailable)
        }
    }
}

// MARK: - Wire reasons

private extension ProductsNativeApi {
    /// What a third-party product is told on an unclassified failure. The real error is logged; a
    /// CoreData or Keychain dump is not for product scripts.
    static let topUpRegistrationFailed = "top-up could not be registered"
    static let topUpStatusUnavailable = "top-up status is unavailable"
}

// MARK: - Payment Request Checks

private extension ProductsNativeApi {
    func requirePaymentsSupport() throws -> PaymentsSupport {
        guard let paymentsSupport else {
            logger.error("Payment feature requested but payments support is unavailable")
            throw ProductNativeApiError.paymentsNotSupported
        }

        return paymentsSupport
    }

    /// Validates spendable balance covers the requested amount.
    ///
    /// If the product has `balanceAccess` permission, returns `insufficientBalance`
    /// (the product already knows balances). Otherwise returns `rejected`
    /// to avoid leaking balance information.
    func checkSufficientBalance(amount: Balance) async throws {
        guard
            try await permissionGuard.consumePermission(
                productId: productId,
                permission: .balanceAccess
            ) else {
            throw PaymentRequestError.rejected
        }

        let coinageService = try requirePaymentsSupport().coinageService
        let balanceService = try await coinageService.coinageBalanceService()

        var spendable = Balance(0)
        for try await value in balanceService.balanceStream.prefix(1) {
            spendable = value.availablePrivate
        }

        if spendable < amount {
            throw PaymentRequestError.insufficientBalance
        }
    }

    /// Shows the payment request approval sheet and suspends until the user decides.
    func awaitUserApproval(amount: Balance, destination: AccountId) async throws {
        let context = PaymentRequestContext(
            productId: productId,
            amountInPlanks: amount,
            destination: destination
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.setContinuation(continuation)
            Task { @MainActor [productsRouter] in
                productsRouter.showPaymentRequest(context: context)
            }
        }
    }
}

// MARK: - Top-Up Source Description

private extension ProductsNativeApi {
    /// Describes the product-facing source as the persisted bytes the claim is later resolved from —
    /// the full derivation **path** for a product account (never a derived key), the raw key otherwise.
    /// Resolution + validation happen later, in `IncomingPaymentSourceResolver`.
    static func incomingPaymentDescriptor(
        from source: PaymentTopUpSource,
        productId: String
    ) throws -> IncomingPaymentSourceDescriptor {
        switch source {
        case let .productAccount(derivationIndex):
            let derivationPath = try ProductAccountId(
                productId: productId,
                derivationIndex: derivationIndex
            ).derivationPath()

            return .productAccount(derivationPath: derivationPath)
        case let .privateKey(secretKey):
            return .privateKey(secretKey: secretKey)
        case let .coins(secretKeys):
            return .coins(secretKeys: secretKeys)
        }
    }
}

// MARK: - Wire Mapping

private extension HostPaymentTopUpError {
    /// The coded error for `error`; anything that is not a classified `IncomingPaymentError` becomes
    /// `unknown` with the generic `unknownReason` rather than the error's own description.
    init(_ error: any Error, unknownReason: String) {
        switch error as? IncomingPaymentError {
        case .alreadyExists: self = .alreadyExists
        case .invalidSource: self = .invalidSource
        case .sourceBusy: self = .sourceBusy
        case .invalidAmount: self = .unknown(reason: "amount must be positive")
        case let .notFound(paymentId): self = .notFound(paymentId)
        case .unknown,
             .none: self = .unknown(reason: unknownReason)
        }
    }
}

private extension HostPaymentTopUpStatus {
    init(status: IncomingPaymentStatus) {
        switch status {
        case .detecting: self = .detecting
        case .claiming: self = .claiming
        case let .claimed(finalized): self = .claimed(finalized: finalized)
        case let .claimedPartially(actualClaimed): self = .claimedPartially(actualClaimed: actualClaimed)
        case .notClaimed: self = .notClaimed
        }
    }
}
