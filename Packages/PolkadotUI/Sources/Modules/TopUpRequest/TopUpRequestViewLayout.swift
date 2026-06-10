import SwiftUI
import DesignSystem

public struct TopUpRequestViewLayout: View {
    public var title: String
    public var amount: String
    public var claimButtonTitle: String
    public var warningMessage: String?
    public var isClaiming: Bool = false
    public var onClaimTapped: () -> Void = {}

    public init(
        title: String,
        amount: String,
        claimButtonTitle: String,
        warningMessage: String? = nil,
        isClaiming: Bool = false,
        onClaimTapped: @escaping () -> Void = {}
    ) {
        self.title = title
        self.amount = amount
        self.claimButtonTitle = claimButtonTitle
        self.warningMessage = warningMessage
        self.isClaiming = isClaiming
        self.onClaimTapped = onClaimTapped
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BottomSheetBaseView {
                VStack(alignment: .center, spacing: 0) {
                    Text(title)
                        .typography(.headlineSmall)
                        .foregroundColor(.fgPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)

                    Text(amount)
                        .typography(.displayLarge)
                        .foregroundColor(.fgPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 80)
                        .padding(.bottom, warningMessage != nil ? 24 : 80)

                    if let warningMessage {
                        Text(warningMessage)
                            .textStyle(.body14Regular())
                            .foregroundColor(.fgWarning)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 56)
                    }

                    Button(action: onClaimTapped) {
                        Group {
                            if isClaiming {
                                ProgressView()
                                    .progressViewStyle(
                                        CircularProgressViewStyle(tint: .fgPrimaryInverted)
                                    )
                            } else {
                                Text(claimButtonTitle)
                                    .typography(.titleMedium)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.mainWhite)
                    .disabled(isClaiming)
                }
            }
        }
    }
}

#Preview {
    TopUpRequestViewLayout(
        title: "Top up from sample-product",
        amount: "$5",
        claimButtonTitle: "Claim",
        warningMessage: "The detected amount differs from the amount stated by the product.",
        isClaiming: false
    )
}
