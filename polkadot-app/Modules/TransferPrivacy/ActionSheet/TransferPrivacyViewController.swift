import UIKit
import PolkadotUI
import UIKit_iOS
import FoundationExt

final class TransferPrivacyViewController: UIViewController, ViewHolder {
    typealias RootViewType = TransferPrivacyViewLayout

    let presenter: TransferPrivacyPresenterProtocol

    init(presenter: TransferPrivacyPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = RootViewType()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupActions()
        presenter.setup()
    }

    private func setupActions() {
        let linkAction = UIAction { [weak presenter] _ in
            presenter?.activateLink()
        }
        rootView.linkButton.addAction(linkAction, for: .touchUpInside)
        let mainAction = UIAction { [weak presenter] _ in
            presenter?.selectMain()
        }
        rootView.mainButton.addAction(mainAction, for: .touchUpInside)
        let secondaryAction = UIAction { [weak presenter] _ in
            presenter?.selectSecondary()
        }
        rootView.secondaryButton.addAction(secondaryAction, for: .touchUpInside)
        let cancelAction = UIAction { [weak presenter] _ in
            presenter?.cancel()
        }
        rootView.cancelButton.addAction(cancelAction, for: .touchUpInside)
    }
}

extension TransferPrivacyViewController: TransferPrivacyViewProtocol {
    func didReceive(viewModel: TransferPrivacyViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}
