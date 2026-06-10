import SwiftUI
import Combine
import PolkadotUI
import DesignSystem

final class TransferActionButtonModel: ObservableObject {
    @Published var title: String = ""
    @Published var isLoading: Bool = false
    @Published var isActive: Bool = true
    var action: () -> Void = {}
}

typealias TransferActionButtonController = UIHostingController<TransferActionButtonView>

struct TransferActionButtonView: View {
    @ObservedObject var model: TransferActionButtonModel

    var body: some View {
        Group {
            if model.isLoading {
                Capsule()
                    .fill(Color.bgActionPrimary)
                    .overlay {
                        ProgressView()
                            .tint(.fgPrimaryInverted)
                    }
                    .frame(height: UIConstants.actionHeight)
                    .disabled(true)
            } else {
                DSButton(
                    model.title,
                    style: .primary,
                    shape: .pill,
                    size: .large,
                    leadingIcon: model.isActive ? .iconArrowUp16 : nil,
                    expands: true,
                    action: model.action
                )
                .disabled(!model.isActive)
            }
        }
    }
}
