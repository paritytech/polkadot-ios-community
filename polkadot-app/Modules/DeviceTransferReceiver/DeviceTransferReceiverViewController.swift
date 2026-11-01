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
        view.backgroundColor = .backgroundPrimary

        presenter.setup()
    }
}

extension DeviceTransferReceiverViewController: DeviceTransferReceiverViewProtocol {}
