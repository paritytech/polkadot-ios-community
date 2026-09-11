import PolkadotUI
import SwiftUI
import UIKit
import UIKit_iOS

final class TopUpMismatchViewController: UIHostingController<TopUpMismatchViewLayout> {
    let presenter: TopUpMismatchPresenterProtocol
    var onDidDisappear: (() -> Void)?

    init(presenter: TopUpMismatchPresenterProtocol) {
        self.presenter = presenter
        let placeholder = TopUpMismatchViewModel()
        super.init(rootView: TopUpMismatchViewLayout(viewModel: placeholder))
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        presenter.setup()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        onDidDisappear?()
        onDidDisappear = nil
    }
}

extension TopUpMismatchViewController: TopUpMismatchViewProtocol {
    func didReceive(viewModel: any TopUpMismatchViewModelProtocol) {
        rootView = TopUpMismatchViewLayout(viewModel: viewModel)
    }
}

extension TopUpMismatchViewController: TopUpAcknowledgementDismissObserving {}

extension TopUpMismatchViewController: ModalPresenterDelegate {
    func presenterShouldHide(_: any ModalPresenterProtocol) -> Bool {
        false
    }
}
