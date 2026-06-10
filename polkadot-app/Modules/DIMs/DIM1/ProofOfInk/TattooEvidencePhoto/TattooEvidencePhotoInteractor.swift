import AVFoundation
import UIKit

final class TattooEvidencePhotoInteractor {
    weak var presenter: TattooEvidencePhotoInteractorOutputProtocol?

    private let photoCaptureService: PhotoCaptureServiceProtocol
    private let fileManager: EvidenceFileManaging
    private let logger: LoggerProtocol

    init(
        photoCaptureService: PhotoCaptureServiceProtocol,
        fileManager: EvidenceFileManaging,
        logger: LoggerProtocol
    ) {
        self.photoCaptureService = photoCaptureService
        self.fileManager = fileManager
        self.logger = logger
    }
}

extension TattooEvidencePhotoInteractor: TattooEvidencePhotoInteractorInputProtocol {
    func setup() {
        photoCaptureService.checkAuthorizationAndSetupSession()
    }

    func capturePhoto() {
        do {
            let targetUrl = try fileManager.preparePhotoEvidenceUrl()
            presenter?.didReceive(state: .capturing)
            photoCaptureService.capturePhoto(withURL: targetUrl)
        } catch {
            presenter?.didReceive(error: .storageError(error))
        }
    }
}

extension TattooEvidencePhotoInteractor: CameraServiceDelegate {
    func didReceivedPhoto(_ photo: UIImage) {
        presenter?.didReceive(state: .captured(photo))
    }

    func didSetup(session: AVCaptureSession) {
        presenter?.didReceive(session: session)
    }

    func didSavePhoto(at url: URL) {
        logger.info("Did save photo to: \(url.absoluteString)")
        presenter?.didSaveCapturedPhoto()
    }

    func didFailToCapturePhoto(error: PhotoCaptureServiceError) {
        presenter?.didReceive(error: .photoCapture(error))
    }
}
