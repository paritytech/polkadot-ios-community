import BigInt
import Foundation
import Coinage
import KeyDerivation
import Products
import SubstrateSdk
import AsyncExtensions

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
        return balanceService.spendableBalanceStream
            .map { balance in
                PaymentBalance(available: balance.totalInPlanks())
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

    func paymentTopUp(amount: Balance, source: PaymentTopUpSource) async throws {
        let coinageService = try requirePaymentsSupport().coinageService
        let contextSource = try resolveTopUpSource(source: source, callingProductId: productId)
        let context = TopUpRequestContext(
            productId: productId,
            amount: amount,
            source: contextSource
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.setContinuation(continuation)
            Task { @MainActor [topUpRequestRouter, coinageService] in
                topUpRequestRouter.showTopUpRequest(
                    context: context,
                    coinageService: coinageService
                )
            }
        }
    }
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
        for try await value in balanceService.spendableBalanceStream.prefix(1) {
            spendable = value.totalInPlanks()
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
            Task { @MainActor [paymentRequestRouter] in
                paymentRequestRouter.showPaymentRequest(context: context)
            }
        }
    }
}

// MARK: - Top-Up Helpers

private extension ProductsNativeApi {
    func resolveTopUpSource(
        source: PaymentTopUpSource,
        callingProductId: ProductId
    ) throws -> TopUpRequestContext.Source {
        switch source {
        case let .productAccount(derivationIndex):
            let accountId = ProductAccountId(
                productId: callingProductId,
                derivationIndex: derivationIndex
            )
            let wallet = DynamicDerivedWallet(
                derivationPath: accountId.derivationPath,
                entropyManager: entropyManager
            )
            return .wallet(wallet)
        case let .privateKey(secretKey):
            return .wallet(DynamicDerivedWallet(secretKeyProvider: { secretKey }))
        case let .coins(secretKeys):
            return .coins(secretKeys: secretKeys)
        }
    }
}
