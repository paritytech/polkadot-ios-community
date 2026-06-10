import BigInt
import Coinage
import Foundation
import SubstrateSdk

enum TopUpRequestInteractorError: Error {
    case noCoinsToClaim
}

@MainActor
final class TopUpRequestInteractor {
    weak var presenter: TopUpRequestInteractorOutputProtocol?

    private let context: TopUpRequestContext
    private let coinageService: any CoinageServicing
    private let logger: LoggerProtocol

    private var claimTask: Task<Void, Never>?
    private var detectTask: Task<Void, Never>?

    nonisolated init(
        context: TopUpRequestContext,
        coinageService: any CoinageServicing,
        logger: LoggerProtocol
    ) {
        self.context = context
        self.coinageService = coinageService
        self.logger = logger
    }

    deinit {
        claimTask?.cancel()
        detectTask?.cancel()
    }
}

extension TopUpRequestInteractor: TopUpRequestInteractorInputProtocol {
    func setup() {
        // Pre-prompt cross-check: warn the user if the on-chain coin total
        // doesn't match the amount the product requested.
        guard case let .coins(secretKeys) = context.source else { return }

        detectTask = Task { [weak self, coinageService, context, logger] in
            do {
                let detected = try await coinageService.transferCoinsFromSecretKeys(
                    secretKeys: secretKeys,
                    transferCoins: false
                )
                self?.handleDetected(detected, requested: context.amount)
            } catch {
                logger.error("Top-up coins detection failed: \(error)")
                self?.handleDetectionFailure()
            }
        }
    }

    func claim() {
        guard claimTask == nil else { return }

        presenter?.didStartClaim()

        claimTask = Task { [weak self, coinageService, context, logger] in
            defer { Task { @MainActor [weak self] in self?.claimTask = nil } }

            do {
                try await self?.performClaim(
                    coinageService: coinageService,
                    context: context
                )
                context.deliverClaimed()
                self?.presenter?.didFinishClaim()
            } catch {
                logger.error("Top-up claim failed: \(error)")
                context.deliverFailed(error)
                self?.presenter?.didFailClaim(error)
            }
        }
    }
}

private extension TopUpRequestInteractor {
    func handleDetected(_ detected: BigUInt, requested: BigUInt) {
        if detected != requested {
            presenter?.didDetectAmountMismatch()
        }
    }

    func handleDetectionFailure() {
        presenter?.didFailDetection()
    }

    nonisolated func performClaim(
        coinageService: any CoinageServicing,
        context: TopUpRequestContext
    ) async throws {
        switch context.source {
        case let .wallet(signerWallet):
            try await coinageService.loadVouchers(
                amount: context.amount,
                externalAssetHolder: signerWallet
            )
        case let .coins(secretKeys):
            let claimed = try await coinageService.transferCoinsFromSecretKeys(
                secretKeys: secretKeys,
                transferCoins: true
            )
            // Zero = no on-chain coins matched the keys; reject instead of delivering a no-op success.
            guard claimed > 0 else {
                throw TopUpRequestInteractorError.noCoinsToClaim
            }
        }
    }
}
