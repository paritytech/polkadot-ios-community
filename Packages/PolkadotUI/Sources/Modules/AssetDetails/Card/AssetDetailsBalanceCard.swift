import SwiftUI
import DesignSystem

public struct AssetDetailsBalanceCard: View {
    let viewModel: ViewModel
    let isUpdating: Bool

    public init(viewModel: ViewModel, isUpdating: Bool) {
        self.viewModel = viewModel
        self.isUpdating = isUpdating
    }

    public var body: some View {
        content
            .cardAspectRatio()
            .bordered(
                width: 0.5,
                cornerRadius: 24,
                gradient: LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: Color(hex: 0xEFEDED).opacity(0.5), location: 0.37)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var content: some View {
        ZStack(alignment: .leading) {
            Image(.cashBg)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(.iconCashLogo)
                    Text(.walletCardTitle)
                        .textStyle(.title18SemiBold())
                }
                Spacer()

                Group {
                    if isUpdating {
                        SwiftUI.Label {
                            Text(.walletCardUpdatingBalance)
                                .textStyle(.body14Regular())
                        } icon: {
                            SpinningUpdateIcon()
                        }
                    } else if let lockedAmount = viewModel.lockedAmount {
                        SwiftUI.Label {
                            Text(lockedAmount)
                                .textStyle(.body14Regular())
                        } icon: {
                            Image(.iconAssetLock)
                                .renderingMode(.template)
                        }
                    }
                }
                .foregroundStyle(.white)

                if let balance = viewModel.balance {
                    Text(balance)
                        .typography(.headlineMedium)
                        .shimmering(active: isUpdating)
                }
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 18)
            .padding(.horizontal, 22)
        }
    }
}

public extension AssetDetailsBalanceCard {
    struct ViewModel {
        let balance: String?
        let lockedAmount: String?

        public init(balance: String?, lockedAmount: String?) {
            self.balance = balance
            self.lockedAmount = lockedAmount
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        AssetDetailsBalanceCard(
            viewModel: AssetDetailsBalanceCard.ViewModel(balance: "123", lockedAmount: "123"),
            isUpdating: true
        )
    }
}
