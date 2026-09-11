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

    /// Scope → approval → privacy confirmation (widened spends only) → register. Uniqueness of
    /// `(product, id)` is validated by the coinage service at registration, so a replay surfaces as
    /// `AlreadyExists` after those steps.
    func requestPayment(amount: Balance, destination: AccountId, id: PaymentRequestId) async throws {
        let externalPaymentService = try requirePaymentsSupport().externalPaymentService

        let spendScope = try await resolveSpendScope(amount: amount)
        try await awaitUserApproval(amount: amount, destination: destination)

        if spendScope == .withConfirmation {
            guard await paymentPrivacyConfirmer.confirmGainingPrivacySpend(amount: amount) else {
                throw HostPaymentRequestError.rejected
            }
        }

        do {
            try await externalPaymentService.initiatePayment(
                origin: productId,
                paymentId: id.toHex(includePrefix: true),
                amountInPlanks: amount,
                destination: destination,
                spendScope: spendScope
            )
        } catch ExternalPaymentError.alreadyExists {
            throw HostPaymentRequestError.alreadyExists
        } catch {
            throw HostPaymentRequestError.wrapping(error)
        }
    }

    func subscribePaymentStatus(id: PaymentRequestId) async throws -> AnyAsyncSequence<HostPaymentStatus> {
        let externalPaymentService = try requirePaymentsSupport().externalPaymentService
        return try externalPaymentService.subscribePaymentStatus(
            origin: productId,
            paymentId: id.toHex(includePrefix: true)
        )
        .map { status in
            switch status {
            case .processing: .processing
            case .completed: .completed
            case let .partiallyCompleted(settled): .partiallyCompleted(settledInPlanks: settled)
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

    /// Picks the scope the payment may draw on — the same widening rule as transfers — or fails when the
    /// amount is unreachable. The permission is only read, never prompted: with `balanceAccess` the
    /// product already knows balances and gets `insufficientBalance`; without it the shortfall is
    /// reported as `rejected` so nothing leaks.
    func resolveSpendScope(amount: Balance) async throws -> SpendScope {
        let coinageService = try requirePaymentsSupport().coinageService
        let balanceService = try await coinageService.coinageBalanceService()

        var balance = CoinageBalance.empty
        for try await value in balanceService.balanceStream.prefix(1) {
            balance = value
        }

        if let scope = PaymentSpendScopeResolver.resolve(balance: balance, amount: amount) {
            return scope
        }

        let knowsBalance = try await permissionGuard.check(productId: productId, permission: .balanceAccess)
        throw knowsBalance ? HostPaymentRequestError.insufficientBalance : HostPaymentRequestError.rejected
    }

    /// Auto-approved for allowlisted products; everyone else sees the payment request sheet.
    func awaitUserApproval(amount: Balance, destination: AccountId) async throws {
        let decision = await paymentApprovalRequester.requestApproval(
            productId: productId,
            amount: amount,
            destination: destination
        )

        guard decision == .approved else {
            throw HostPaymentRequestError.rejected
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
