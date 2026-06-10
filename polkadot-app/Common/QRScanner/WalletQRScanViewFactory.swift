import Foundation

enum WalletQRScanViewFactory {
    static func createView(
        for delegate: WalletQRScanDelegate
    ) -> QRScannerViewProtocol? {
        let processingQueue = QRCaptureService.processingQueue
        let qrService = QRCaptureService(delegate: nil, delegateQueue: processingQueue)
        let qrExtractor = QRExtractionService(processingQueue: processingQueue)

        let wireframe = QRScannerWireframe()

        let presenter = WalletQRScanPresenter(
            matcher: AddressQRMatcher(),
            wireframe: wireframe,
            errorDisplayFactory: QRScannerErrorDisplayFactory(),
            delegate: delegate,
            dsfinvkParser: W3sDsfinvkReceiptParser(),
            acceptedURLSchemes: acceptedDeeplinkSchemes(),
            qrScanService: qrService,
            qrExtractionService: qrExtractor
        )

        let view = QRScannerViewController(presenter: presenter)

        presenter.view = view

        return view
    }

    // Allowlist confines the scanner to our own deeplinks; rejects tel:/sms:/etc.
    // Both build flavors listed because the active scheme depends on the configuration.
    private static func acceptedDeeplinkSchemes() -> Set<String> {
        ["polkadotapp", "polkadotappdev"]
    }
}
