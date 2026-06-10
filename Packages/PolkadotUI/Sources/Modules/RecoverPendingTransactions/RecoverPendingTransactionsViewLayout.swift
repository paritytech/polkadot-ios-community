import SwiftUI
import DesignSystem

public struct RecoverPendingTransactionsViewLayout: View {
    @State public var viewModel = RecoverPendingTransactionsViewModel()

    public init() {}

    public var body: some View {
        ZStack(alignment: .center) {
            VStack(alignment: .center, spacing: DSSpacings.large) {
                VStack(spacing: DSSpacings.extraLarge) {
                    Text(viewModel.headlineText)
                        .typography(.headlineSmall)
                        .foregroundStyle(.fgPrimary)
                        .multilineTextAlignment(.center)

                    Text(viewModel.descriptionText)
                        .typography(.paragraphLarge)
                        .foregroundStyle(.fgSecondary)
                        .multilineTextAlignment(.center)

                    Text(viewModel.noteText)
                        .typography(.paragraphLarge)
                        .foregroundStyle(.fgTertiary)
                        .multilineTextAlignment(.center)
                }

                actionButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay(alignment: .bottom, content: {
            if let bannerText = viewModel.bannerText {
                Text(bannerText)
                    .typography(.bodyMedium)
                    .foregroundStyle(bannerColor(for: viewModel.bannerStyle))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.bgSurfaceNested, in: RoundedRectangle(cornerRadius: 12))
            }
        })
        .padding(DSSpacings.large)
    }

    private var actionButton: some View {
        Button(action: { viewModel.onTap?() }) {
            ZStack {
                HStack(spacing: DSSpacings.small) {
                    LoadingSpinner(lineWidth: 2, strokeStyle: .fgSecondary)
                        .frame(width: 20, height: 20)
                    Text(viewModel.recoveringText)
                }
                .opacity(viewModel.isLoading ? 1 : 0)

                Text(viewModel.buttonTitle)
                    .opacity(viewModel.isLoading ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.ds(style: .primary, shape: .pill, size: .large))
        .disabled(viewModel.isLoading)
    }

    private func bannerColor(for style: RecoverPendingTransactionsViewModel.BannerStyle) -> Color {
        switch style {
        case .success:
            Color.fgSuccess
        case .error:
            Color.fgError
        }
    }
}

#Preview {
    RecoverPendingTransactionsViewLayout()
}
