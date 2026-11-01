import UIKit
import SwiftUI
import PolkadotUI

final class DeviceTransferReceiverViewController: UIHostingController<DeviceTransferReceiverViewLayout> {
    let presenter: DeviceTransferReceiverPresenterProtocol

    init(presenter: DeviceTransferReceiverPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: DeviceTransferReceiverViewLayout())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .bgSurfaceMain

        rootView.viewModel.onStart = { [weak self] in self?.presenter.startTransfer() }
        rootView.viewModel.onCancel = { [weak self] in self?.presenter.cancelTransfer() }
        rootView.viewModel.onContinue = { [weak self] in self?.presenter.complete() }

        presenter.setup()
    }
}

extension DeviceTransferReceiverViewController: DeviceTransferReceiverViewProtocol {
    func didReceive(screen: DeviceTransferReceiverScreen, oldPhone: DeviceTransferOldPhone?) {
        rootView.viewModel.screen = screen
        rootView.viewModel.oldPhone = oldPhone
    }
}
