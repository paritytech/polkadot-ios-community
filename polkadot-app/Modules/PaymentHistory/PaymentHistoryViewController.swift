import UIKit
import SwiftUI
import PolkadotUI

final class PaymentHistoryViewController: UIHostingController<PaymentHistoryViewLayout> {
    let presenter: PaymentHistoryPresenterProtocol
    private let viewModel: PaymentHistoryViewModel

    init(presenter: PaymentHistoryPresenterProtocol) {
        self.presenter = presenter
        let viewModel = PaymentHistoryViewModel()
        self.viewModel = viewModel
        super.init(rootView: PaymentHistoryViewLayout(viewModel: viewModel))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = "Payment History"

        presenter.setup()
    }
}

extension PaymentHistoryViewController: PaymentHistoryViewProtocol {
    func applyItems(_ items: [PaymentHistoryViewModel.Item]) {
        viewModel.items = items
    }
}
