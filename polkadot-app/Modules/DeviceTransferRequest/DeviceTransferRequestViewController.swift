import UIKit
import SwiftUI
import PolkadotUI
import UIKit_iOS

final class DeviceTransferRequestViewController: UIHostingController<DeviceTransferRequestViewLayout> {
    let presenter: DeviceTransferRequestPresenterProtocol

    init(presenter: DeviceTransferRequestPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: DeviceTransferRequestViewLayout())
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        rootView.viewModel.onTransfer = { [weak self] in self?.presenter.transfer() }
        rootView.viewModel.onDecline = { [weak self] in self?.presenter.decline() }

        presenter.setup()
    }
}

extension DeviceTransferRequestViewController: DeviceTransferRequestViewProtocol {
    func didReceive(newPhone: DeviceTransferPhone) {
        rootView.viewModel.newPhone = newPhone
    }
}

/// The request needs an answer, so the sheet can't be swiped away.
extension DeviceTransferRequestViewController: ModalPresenterDelegate {
    func presenterShouldHide(_: any ModalPresenterProtocol) -> Bool {
        false
    }
}
