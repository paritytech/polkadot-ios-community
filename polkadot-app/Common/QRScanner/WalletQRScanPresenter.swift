import Foundation

final class WalletQRScanPresenter: QRScannerPresenter {
    weak var delegate: WalletQRScanDelegate?
    private let dsfinvkParser: W3sDsfinvkReceiptParsing
    private let acceptedURLSchemes: Set<String>
    private var lastHandledCode: String?

    let matcher: AddressQRMatching

    init(
        matcher: AddressQRMatching,
        wireframe: QRScannerWireframeProtocol,
        errorDisplayFactory: QRScannerErrorDisplayFactoryProtocol,
        delegate: WalletQRScanDelegate,
        dsfinvkParser: W3sDsfinvkReceiptParsing,
        acceptedURLSchemes: Set<String>,
        qrScanService: QRCaptureServiceProtocol,
        qrExtractionService: QRExtractionServiceProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.delegate = delegate
        self.dsfinvkParser = dsfinvkParser
        self.acceptedURLSchemes = acceptedURLSchemes
        self.matcher = matcher

        super.init(
            wireframe: wireframe,
            qrScanService: qrScanService,
            qrExtractionService: qrExtractionService,
            errorDisplayFactory: errorDisplayFactory,
            logger: logger
        )
    }

    override func handle(code: String) {
        guard lastHandledCode != code else { return }
        lastHandledCode = code

        if let receipt = dsfinvkParser.tryParse(code) {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.walletQRScanDidReceiveDsfinvkReceipt(receipt)
            }
            return
        }

        if let address = matcher.match(code: code),
           let accountId = try? address.toAccountId() {
            let url = AppConfig.DeepLink.chat(Chat.Id.person(accountId), force: false)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.walletQRScanDidReceiveURL(url)
            }
            return
        }

        if let url = URL(string: code),
           let scheme = url.scheme?.lowercased(),
           acceptedURLSchemes.contains(scheme) {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.walletQRScanDidReceiveURL(url)
            }
            return
        }

        // Allow retrying the same QR after the failure feedback.
        lastHandledCode = nil
        DispatchQueue.main.async { [weak self] in
            self?.handleFailure()
        }
    }

    private func handleFailure() {
        let message = errorDisplayFactory.createMatcherFailedString()
        view?.present(message: message, animated: true)
    }
}
