import Foundation
import Coinage
import ChainRegistry
import SubstrateSdk

/// Decides whether a product payment needs device authentication, from the user's total Cash.
protocol PaymentConfirmationGating: Sendable {
    func requiresAuthentication(amount: Balance) async -> Bool
}

final class PaymentConfirmationGate: PaymentConfirmationGating {
    private let coinageService: CoinageServicing?
    private let chainAssetProvider: @Sendable () async -> ChainAsset?
    private let rule: ConfirmationGateRuleProtocol

    init(
        coinageService: CoinageServicing?,
        chainAssetProvider: @escaping @Sendable () async -> ChainAsset?,
        rule: ConfirmationGateRuleProtocol
    ) {
        self.coinageService = coinageService
        self.chainAssetProvider = chainAssetProvider
        self.rule = rule
    }

    func requiresAuthentication(amount: Balance) async -> Bool {
        guard let chainAsset = await chainAssetProvider() else { return true }

        let amountCash = amount.decimal(assetInfo: chainAsset.assetDisplayInfo)
        let totalCash = await totalCash(chainAsset: chainAsset)

        return rule.requiresAuthentication(amount: amountCash, totalCash: totalCash)
    }
}

private extension PaymentConfirmationGate {
    func totalCash(chainAsset: ChainAsset) async -> Decimal? {
        guard let coinageService else { return nil }

        do {
            let balanceService = try await coinageService.coinageBalanceService()
            for try await balance in balanceService.balanceStream.prefix(1) {
                return balance.total.decimal(assetInfo: chainAsset.assetDisplayInfo)
            }
            return nil
        } catch {
            return nil
        }
    }
}
