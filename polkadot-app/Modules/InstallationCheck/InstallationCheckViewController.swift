import UIKit
import SwiftUI
import PolkadotUI

final class InstallationCheckViewController: UIHostingController<InstallationCheckViewLayout> {
    let presenter: InstallationCheckPresenterProtocol

    init(presenter: InstallationCheckPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: InstallationCheckViewLayout())
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

extension InstallationCheckViewController: InstallationCheckViewProtocol {}
