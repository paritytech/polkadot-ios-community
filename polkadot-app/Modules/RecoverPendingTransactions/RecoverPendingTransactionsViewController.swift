import UIKit
import SwiftUI
import PolkadotUI

final class RecoverPendingTransactionsViewController: UIHostingController<RecoverPendingTransactionsViewLayout> {
    let presenter: RecoverPendingTransactionsPresenterProtocol

    init(presenter: RecoverPendingTransactionsPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: RecoverPendingTransactionsViewLayout())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = String(localized: .recoverPendingTransactionsTitle)

        rootView.viewModel.headlineText = String(localized: .recoverPendingTransactionsHeadline)
        rootView.viewModel.descriptionText = String(localized: .recoverPendingTransactionsDescription)
        rootView.viewModel.noteText = String(localized: .recoverPendingTransactionsNote)
        rootView.viewModel.buttonTitle = String(localized: .recoverPendingTransactionsButton)
        rootView.viewModel.recoveringText = String(localized: .recoverPendingTransactionsRecovering)

        rootView.viewModel.onTap = { [weak self] in
            self?.presenter.didTapRecover()
        }

        presenter.setup()
    }
}

extension RecoverPendingTransactionsViewController: RecoverPendingTransactionsViewProtocol {
    func applyState(_ viewState: RecoverPendingTransactionsViewState) {
        rootView.viewModel.isLoading = viewState.isLoading
        rootView.viewModel.bannerText = viewState.bannerText
        rootView.viewModel.bannerStyle = viewState.bannerStyle
    }
}
