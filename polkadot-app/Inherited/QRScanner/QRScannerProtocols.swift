import Foundation
import AVFoundation
import UIKitExt

protocol QRScannerViewProtocol: ControllerBackedProtocol {
    func didReceive(session: AVCaptureSession)
    func present(message: String, animated: Bool, autoDismiss: Bool)
}

extension QRScannerViewProtocol {
    func present(message: String, animated: Bool) {
        present(message: message, animated: animated, autoDismiss: true)
    }
}

protocol QRScannerWireframeProtocol {
    func askOpenSettings(from view: QRScannerViewProtocol?)
}

protocol QRScannerPresenterProtocol: AnyObject {
    func setup()
    func viewWillAppear()
    func viewDidDisappear()
}
