import UIKit
import SwiftUI
import PolkadotUI

final class AppDetailViewController: UIHostingController<AppDetailViewLayout> {
    let presenter: AppDetailPresenterProtocol

    init(presenter: AppDetailPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: AppDetailViewLayout())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .bgSurfaceMain

        rootView.viewModel.onPermissionsTap = { [weak self] in
            self?.presenter.didTapPermissions()
        }

        presenter.setup()
    }
}

extension AppDetailViewController: AppDetailViewProtocol {
    func didReceive(name: String) {
        rootView.viewModel.name = name
    }
}
