import Foundation

final class WalletQRScanPresenter: QRScannerPresenter {
    private static let rescanIdleInterval: TimeInterval = 0.75

    weak var delegate: WalletQRScanDelegate?
    private let dsfinvkParser: W3sDsfinvkReceiptParsing
    private let acceptedURLSchemes: Set<String>
    private var lastHandledCode: String?
    private var lastDetectionDate: Date?

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
        // Capture emits continuously while a code stays in frame; a gap means the user
        // aimed away, which is the only signal that re-handling the same code is intended.
        let now = Date()
        let wasIdle = lastDetectionDate.map { now.timeIntervalSince($0) > Self.rescanIdleInterval } ?? true
        lastDetectionDate = now

        if wasIdle {
            lastHandledCode = nil
        }

        guard view?.isCoveredByModal == false else { return }
        guard lastHandledCode != code else { return }
        lastHandledCode = code

        if let receipt = dsfinvkParser.tryParse(code) {
            delegate?.walletQRScanDidReceiveDsfinvkReceipt(receipt)
            return
        }

        if let address = matcher.match(code: code),
           let accountId = try? address.toAccountId() {
            let url = AppConfig.DeepLink.chat(Chat.Id.person(accountId), force: false)
            delegate?.walletQRScanDidReceiveURL(url)
            return
        }

        if let url = URL(string: code),
           let scheme = url.scheme?.lowercased(),
           acceptedURLSchemes.contains(scheme) {
            delegate?.walletQRScanDidReceiveURL(url)
            return
        }

        // Allow retrying the same QR after the failure feedback.
        lastHandledCode = nil
        handleFailure()
    }

    private func handleFailure() {
        let message = errorDisplayFactory.createMatcherFailedString()
        view?.present(message: message, animated: true)
    }

    override func viewDidAppear() {
        lastHandledCode = nil
        lastDetectionDate = nil
        super.viewDidAppear()
    }
}
