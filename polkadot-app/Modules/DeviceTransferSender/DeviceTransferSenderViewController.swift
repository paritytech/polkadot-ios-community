import UIKit
import SwiftUI
import PolkadotUI

final class DeviceTransferSenderViewController: UIHostingController<DeviceTransferSenderViewLayout> {
    let presenter: DeviceTransferSenderPresenterProtocol

    init(presenter: DeviceTransferSenderPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: DeviceTransferSenderViewLayout())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .bgSurfaceMain

        rootView.viewModel.onCancel = { [weak self] in self?.presenter.cancelTransfer() }
        rootView.viewModel.onBackToChats = { [weak self] in self?.presenter.backToChats() }

        presenter.setup()
    }
}

extension DeviceTransferSenderViewController: DeviceTransferSenderViewProtocol {
    func didReceive(screen: DeviceTransferSenderScreen, newPhone: DeviceTransferPhone) {
        rootView.viewModel.screen = screen
        rootView.viewModel.newPhone = newPhone
    }
}
