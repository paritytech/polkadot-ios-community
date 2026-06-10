import Foundation
import Operation_iOS
import ExtrinsicService
import SubstrateSdk
import SDKLogger
import OperationExt
import Coinage
import KeyDerivation
import StructuredConcurrency
import BigInt

struct TransferAmountDependency {
    let wallet: () -> WalletManaging
    let recipient: () -> RecipientModel
    let chainAsset: () -> ChainAsset
    let contactsRepository: () -> AnyDataProviderRepository<RecentContactModel>
    let operationQueue: () -> OperationQueue
    let coinageService: () -> CoinageServicing
    let transferMethod: () -> TransferMethod
    let chatSubmitter: () -> TransferChatSubmitting
}

final class TransferAmountInteractor {
    weak var presenter: TransferAmountInteractorOutputProtocol?

    let wallet: WalletManaging
    let accountId: AccountId
    let recipient: RecipientModel
    let chainAsset: ChainAsset
    let operationQueue: OperationQueue

    let contactsRepository: AnyDataProviderRepository<RecentContactModel>
    let logger: SDKLoggerProtocol?
    let coinageService: CoinageServicing
    let transferMethod: TransferMethod
    let chatSubmitter: TransferChatSubmitting

    private var coinageBalanceTask: Task<Void, Never>?
    private var lockedBalanceTask: Task<Void, Never>?

    init(
        dependencies: TransferAmountDependency,
        logger: SDKLoggerProtocol?
    ) throws {
        wallet = dependencies.wallet()
        accountId = try wallet.getRawPublicKey()
        recipient = dependencies.recipient()
        chainAsset = dependencies.chainAsset()
        operationQueue = dependencies.operationQueue()
        contactsRepository = dependencies.contactsRepository()
        coinageService = dependencies.coinageService()
        transferMethod = dependencies.transferMethod()
        chatSubmitter = dependencies.chatSubmitter()
        self.logger = logger
    }
}

// MARK: - TransferAmountInteractorInputProtocol

extension TransferAmountInteractor: TransferAmountInteractorInputProtocol {
    var senderAddress: AccountId {
        accountId
    }

    func setup() {
        startCoinageBalanceObservation()
    }

    func retrySetup() {
        startCoinageBalanceObservation()
    }

    func previewTransfer(for amount: Decimal) async throws -> TransferPreviewValidation {
        guard let planks = chainAsset.asset.planks(from: amount) else {
            throw TransferAmountInteractorError.internalError
        }

        switch transferMethod {
        case .coinage:
            let preview = try await coinageService.previewTransfer(for: planks)
            return .coinage(preview)
        case .externalPayment:
            let preview = try await coinageService.previewExternalPayment(for: planks)
            return .externalPayment(preview)
        }
    }

    func confirmTransfer(
        validation: TransferPreviewValidation,
        sendFullAmount: Bool
    ) async throws {
        coinageBalanceTask?.cancel()
        coinageBalanceTask = nil
        lockedBalanceTask?.cancel()
        lockedBalanceTask = nil

        do {
            switch validation {
            case let .coinage(preview):
                try await confirmCoinageTransfer(preview: preview, sendFullAmount: sendFullAmount)
            case let .externalPayment(preview):
                try await confirmExternalPayment(preview: preview)
            }
        } catch {
            logger?.error("Did fail transfer: \(error)")

            retrySetup()
            throw TransferAmountInteractorError.transactionFailed(error)
        }
    }

    func saveRecentContact() {
        let contact = RecentContactModel(
            accountID: recipient.accountId,
            chainAssetID: chainAsset.chainAssetId
        )
        let saveOperation = contactsRepository.saveOperation {
            [contact]
        } _: {
            []
        }
        execute(
            operation: saveOperation,
            inOperationQueue: operationQueue,
            runningCallbackIn: .main
        ) { [weak self] result in
            switch result {
            case .success:
                self?.logger?.info("Recent Contact successfully saved in the database")
            case let .failure(error):
                self?.logger?.debug(error.localizedDescription)
            }
        }
    }
}

// MARK: - Coinage Transfer

private extension TransferAmountInteractor {
    func confirmCoinageTransfer(preview: TransferPreview, sendFullAmount: Bool) async throws {
        let result = sendFullAmount ? preview.selectionResult : preview.nonDegradedResult
        let memo = try await coinageService.executeTransfer(result: result)
        do {
            try await chatSubmitter.sendChatMessage(memo, to: recipient.accountId)
        } catch {
            if chatSubmitter.isFailureFatal {
                throw error
            }
            logger?.error("Non-fatal chat submitter failure: \(error)")
        }
    }
}

// MARK: - External Payment

private extension TransferAmountInteractor {
    func confirmExternalPayment(preview: ExternalPaymentPreview) async throws {
        let paymentId = try await coinageService.initiateExternalPayment(
            origin: recipient.accountId.toAddress(using: .genericFormat),
            amountInPlanks: preview.fullAmount,
            destination: recipient.accountId
        )

        for try await status in try await coinageService.subscribeExternalPaymentStatus(paymentId: paymentId) {
            switch status {
            case .completed:
                return
            case let .failed(reason):
                throw TransferAmountInteractorError.transactionFailed(
                    ExternalPaymentError(reason: reason)
                )
            case .processing:
                continue
            }
        }

        throw TransferAmountInteractorError.internalError
    }
}

// MARK: - Balance Observation

private extension TransferAmountInteractor {
    func startCoinageBalanceObservation() {
        coinageBalanceTask?.cancel()
        lockedBalanceTask?.cancel()
        let service = coinageService
        coinageBalanceTask = Task { [weak self] in
            do {
                let balanceService = try await service.coinageBalanceService()
                for try await balance in balanceService.spendableBalanceStream.removeDuplicates() {
                    let breakdown = TransferSpendableBreakdown(
                        secured: balance.fullPrivacy.planks,
                        lowPrivacy: balance.degraded.planks
                    )
                    await self?.presenter?.didReceive(spendableBreakdown: breakdown)
                }
            } catch {
                self?.logger?.error("Failed to observe coinage balance: \(error)")
            }
        }

        lockedBalanceTask = Task { [weak self] in
            do {
                let balanceService = try await service.coinageBalanceService()
                for try await locked in balanceService.lockedBalanceStream.removeDuplicates() {
                    await self?.presenter?.didReceive(lockedBalance: locked.planks)
                }
            } catch {
                self?.logger?.error("Failed to observe locked balance: \(error)")
            }
        }
    }
}

// MARK: - DEBUG

extension TransferAmountInteractor {
    #if TESTNET_FEATURE
        func previewStrategy(for amount: Decimal) {
            let service = coinageService
            let method = transferMethod
            Task { [weak self, chainAsset] in
                do {
                    guard let plank = chainAsset.asset.planks(from: amount) else {
                        throw TransferAmountInteractorError.internalError
                    }

                    let fetcher: TransferDebugInfoFetching =
                        switch method {
                        case .coinage:
                            CoinageDebugInfoFetcher(coinageService: service)
                        case .externalPayment:
                            ExternalPaymentDebugInfoFetcher(coinageService: service)
                        }

                    let debugInfo = try await fetcher.fetchDebugInfo(for: plank)
                    await self?.presenter?.didReceive(strategyDebugInfo: debugInfo)
                } catch {
                    self?.logger?.error("Strategy preview failed: \(error)")
                    await self?.presenter?.didReceive(strategyDebugInfo: nil)
                }
            }
        }
    #endif
}

private extension AssetModel {
    func planks(from decimal: Decimal) -> BigUInt? {
        decimal.toSubstrateAmount(precision: decimalPrecision)
    }
}
