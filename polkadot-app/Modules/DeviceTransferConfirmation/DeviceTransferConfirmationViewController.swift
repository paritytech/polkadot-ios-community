import UIKit
import FoundationExt
import PolkadotUI

final class DeviceTransferConfirmationViewController: UIViewController, ViewHolder {
    typealias RootViewType = DeviceTransferConfirmationViewLayout

    private let viewModel: DeviceTransferConfirmationViewLayout.ViewModel
    private let onConfirm: () -> Void

    init(viewModel: DeviceTransferConfirmationViewLayout.ViewModel, onConfirm: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = DeviceTransferConfirmationViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        rootView.bind(viewModel: viewModel)
        rootView.confirmButton.addTarget(self, action: #selector(handleConfirm), for: .touchUpInside)
        rootView.dismissButton.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
    }
}

private extension DeviceTransferConfirmationViewController {
    @objc
    func handleConfirm() {
        dismiss(animated: true) { [onConfirm] in
            onConfirm()
        }
    }

    @objc
    func handleDismiss() {
        dismiss(animated: true)
    }
}
