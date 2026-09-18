import UIKit
import FoundationExt

final class RootInitViewController: UIViewController, ViewHolder {
    typealias RootViewType = RootInitViewLayout

    var presenter: RootPresenterProtocol?

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = RootInitViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.delegate = self
    }
}

extension RootInitViewController: RootViewProtocol {
    func didReceive(viewModel: RootInitViewLayout.ViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}

extension RootInitViewController: RootInitViewLayoutDelegate {
    func didTapRetry() {
        presenter?.retry()
    }
}
