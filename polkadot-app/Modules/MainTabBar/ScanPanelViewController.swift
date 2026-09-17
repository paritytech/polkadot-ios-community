import UIKit
import FoundationExt

/// Composes the scan panel's content so Common/QRScanner stays free of contact-search knowledge.
final class ScanPanelViewController: UIViewController, ViewHolder {
    typealias RootViewType = ScanPanelViewLayout

    private let scannerController: UIViewController & ScanPanelScannerControlling

    var onEditingDidBegin: (() -> Void)?
    var onEditingDidEnd: (() -> Void)?

    init(scannerController: UIViewController & ScanPanelScannerControlling) {
        self.scannerController = scannerController
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

        setupSearchHeader()
    }
}

// MARK: - Private

private extension ScanPanelViewController {
    func setupSearchHeader() {
        let searchField = rootView.searchRow.searchField

        rootView.searchRow.cancelHandler = { [weak searchField] in
            searchField?.resignFirstResponder()
        }

        rootView.onCameraTapped = { [weak searchField] in
            searchField?.resignFirstResponder()
        }

        searchField.addTarget(self, action: #selector(editingDidBegin), for: .editingDidBegin)
        searchField.addTarget(self, action: #selector(editingDidEnd), for: .editingDidEnd)

        rootView.searchRow.setCancelVisible(false)
    }

    @objc
    func editingDidBegin() {
        applySearchFieldFocused(true)
        onEditingDidBegin?()
    }

    @objc
    func editingDidEnd() {
        applySearchFieldFocused(false)
        onEditingDidEnd?()
    }

    /// Focusing the field shrinks the camera to a thumbnail and disarms recognition, so a code
    /// cannot be picked up from the sliver of preview left behind the keyboard.
    func applySearchFieldFocused(_ focused: Bool) {
        scannerController.setRecognitionArmed(!focused)
        scannerController.setPreviewCompact(focused)
        rootView.setCameraCompact(focused)
        rootView.searchRow.setCancelVisible(focused)
    }
}
