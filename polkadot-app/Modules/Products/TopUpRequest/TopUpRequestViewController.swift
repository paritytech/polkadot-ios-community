import PolkadotUI
import SwiftUI
import UIKit
import UIKit_iOS

final class TopUpRequestViewController: UIHostingController<TopUpRequestViewLayout> {
    let presenter: TopUpRequestPresenterProtocol

    init(presenter: TopUpRequestPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: TopUpRequestViewLayout(
            title: "",
            amount: "",
            claimButtonTitle: ""
        ))
        // prevent dismissal via gestures outside of the bounds
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupHandlers()
        presenter.setup()
    }

    private func setupHandlers() {
        rootView.onClaimTapped = { [weak presenter] in
            presenter?.didTapClaim()
        }
    }
}

extension TopUpRequestViewController: TopUpRequestViewProtocol {
    func didReceive(title: String, amount: String, claimButtonTitle: String) {
        rootView.title = title
        rootView.amount = amount
        rootView.claimButtonTitle = claimButtonTitle
    }

    func didReceive(isClaiming: Bool) {
        rootView.isClaiming = isClaiming
    }

    func didReceive(warningMessage: String?) {
        rootView.warningMessage = warningMessage
    }
}

extension TopUpRequestViewController: ModalPresenterDelegate {
    func presenterShouldHide(_: any ModalPresenterProtocol) -> Bool {
        false
    }

    func presenterDidHide(_: any ModalPresenterProtocol) {}
}
