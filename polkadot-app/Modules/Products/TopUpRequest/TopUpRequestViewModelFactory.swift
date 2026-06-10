import Foundation
import Products
import SubstrateSdk

protocol TopUpRequestViewModelMaking {
    func formatTitle(productId: ProductId) -> String
    func formatAmount(_ balance: Balance) -> String
    func claimButtonTitle() -> String
    func amountMismatchWarning() -> String
    func amountDetectionFailedWarning() -> String
}

final class TopUpRequestViewModelFactory {
    private let chainAsset: ChainAsset
    private let formatterFactory: AssetBalanceFormatterFactoryProtocol

    init(
        chainAsset: ChainAsset,
        formatterFactory: AssetBalanceFormatterFactoryProtocol = AssetBalanceFormatterFactory()
    ) {
        self.chainAsset = chainAsset
        self.formatterFactory = formatterFactory
    }
}

extension TopUpRequestViewModelFactory: TopUpRequestViewModelMaking {
    func formatTitle(productId: ProductId) -> String {
        String(localized: .Products.topUpTitle(productId: productId))
    }

    func formatAmount(_ balance: Balance) -> String {
        let decimalAmount = balance.decimal(assetInfo: chainAsset.asset.digitalDollarDisplayInfo)

        let formatter = formatterFactory
            .createTokenFormatter(for: chainAsset.asset.digitalDollarDisplayInfo)
            .value(for: .current)

        return formatter.stringFromDecimal(decimalAmount) ?? ""
    }

    func claimButtonTitle() -> String {
        String(localized: .Products.topUpClaim)
    }

    func amountMismatchWarning() -> String {
        String(localized: .Products.topUpAmountMismatchWarning)
    }

    func amountDetectionFailedWarning() -> String {
        String(localized: .Products.topUpAmountDetectionFailedWarning)
    }
}
