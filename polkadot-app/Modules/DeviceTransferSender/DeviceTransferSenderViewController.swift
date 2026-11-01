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

        presenter.setup()
    }
}

extension DeviceTransferSenderViewController: DeviceTransferSenderViewProtocol {}
