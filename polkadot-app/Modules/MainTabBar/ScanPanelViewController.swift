import UIKit
import FoundationExt

/// Composes the scan panel's content so Common/QRScanner stays free of contact-search knowledge.
final class ScanPanelViewController: UIViewController, ViewHolder {
    typealias RootViewType = ScanPanelViewLayout

    private let scannerController: UIViewController
    private let onSearchTap: () -> Void

    init(scannerController: UIViewController, onSearchTap: @escaping () -> Void) {
        self.scannerController = scannerController
        self.onSearchTap = onSearchTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = ScanPanelViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(scannerController)
        rootView.setupScannerView(scannerController.view)
        scannerController.didMove(toParent: self)

        rootView.searchButton.onTap = { [weak self] in
            self?.onSearchTap()
        }
    }
}
