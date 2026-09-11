import PolkadotUI
import SwiftUI
import UIKit
import UIKit_iOS

final class TopUpErrorViewController: UIHostingController<TopUpErrorViewLayout> {
    let presenter: TopUpErrorPresenterProtocol
    var onDidDisappear: (() -> Void)?

    init(presenter: TopUpErrorPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: TopUpErrorViewLayout())
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        onDidDisappear?()
        onDidDisappear = nil
    }

    private func setupHandlers() {
        rootView.onCloseTapped = { [weak presenter] in
            presenter?.didTapClose()
        }
    }
}

extension TopUpErrorViewController: TopUpErrorViewProtocol {
    func didReceive(title: String, message: String, closeButtonTitle: String) {
        rootView.title = title
        rootView.message = message
        rootView.closeButtonTitle = closeButtonTitle
    }
}

extension TopUpErrorViewController: TopUpAcknowledgementDismissObserving {}

extension TopUpErrorViewController: ModalPresenterDelegate {
    func presenterShouldHide(_: any ModalPresenterProtocol) -> Bool {
        false
    }
}
