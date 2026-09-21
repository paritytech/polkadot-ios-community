import SwiftUI
import PolkadotUI
import DesignSystem

struct RootViewLayout: View {
    var viewModel: ViewModel
    var onRetry: () -> Void

    init(
        viewModel: ViewModel = .loading(hint: nil),
        onRetry: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onRetry = onRetry
    }

    var body: some View {
        ZStack {
            Color.bgSurfaceMain
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Image(.polkadotLogoLoading)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Color.fgPrimary)

                switch viewModel {
                case let .loading(hint):
                    if let hint {
                        Text(hint)
                            .typography(.bodyMedium)
                            .foregroundColor(.fgTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                case let .failed(issue):
                    VStack(spacing: 0) {
                        Text(issue.title)
                            .typography(.headlineSmall)
                            .foregroundColor(.fgPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(issue.subtitle)
                            .typography(.bodyMedium)
                            .foregroundColor(.fgTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)

                        DSButton(
                            String(localized: .rootInitFailureAction),
                            style: .secondary,
                            action: onRetry
                        )
                        .padding(.top, 16)
                    }
                    .transition(.opacity)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel)
    }
}

extension RootViewLayout {
    enum ViewModel: Equatable {
        struct Issue: Equatable {
            let title: String
            let subtitle: String
        }

        case loading(hint: String?)
        case failed(Issue)
    }
}

#Preview {
    VStack {
        RootViewLayout(
            viewModel: .loading(hint: "Setting up...")
        )

        Divider()

        RootViewLayout(
            viewModel: .failed(
                RootViewLayout.ViewModel.Issue(
                    title: "Failed to Load",
                    subtitle: "Please check your connection and try again."
                )
            )
        )
    }
}
