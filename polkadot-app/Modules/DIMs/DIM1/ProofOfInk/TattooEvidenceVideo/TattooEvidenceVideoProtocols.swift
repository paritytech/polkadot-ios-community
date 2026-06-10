import AVFoundation
import UIKitExt

protocol TattooEvidenceVideoViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: TattooEvidenceVideoViewModel)
}

protocol TattooEvidenceVideoPresenterProtocol: AnyObject {
    func setup()
    func toggleRecording()
    func openTips()
}

protocol TattooEvidVideoInteractorInputProtocol: AnyObject {
    func setup()
    func start()
    func complete()
    func discard()
}

protocol TattooEvidVideoInteractorOutputProtocol: AnyObject {
    func didReceive(captureSession: AVCaptureSession)
    func didDiscardRecording()
    func didCompleteRecording(with urls: [URL])
    func didReceive(error: TattooEvidVideoInteractorError)
}

protocol TattooEvidenceVideoWireframeProtocol: AlertPresentable, ErrorPresentable,
    ApplicationSettingsPresentable {
    func showTips(from view: TattooEvidenceVideoViewProtocol?)
    func showPreview(from view: TattooEvidenceVideoViewProtocol?, recordings: [URL])
}
