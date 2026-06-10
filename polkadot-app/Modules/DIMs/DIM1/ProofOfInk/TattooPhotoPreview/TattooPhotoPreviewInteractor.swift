import UIKit
import Operation_iOS

final class TattooPhotoPreviewInteractor {
    weak var presenter: TattooPhotoViewInteractorOutputProtocol?

    let localStateRepository: AnyDataProviderRepository<EvidenceSubmission.LocalState>
    let fileManager: EvidenceFileManaging
    let operationQueue: OperationQueue

    init(
        fileManager: EvidenceFileManaging,
        localStateRepository: AnyDataProviderRepository<EvidenceSubmission.LocalState>,
        operationQueue: OperationQueue
    ) {
        self.fileManager = fileManager
        self.localStateRepository = localStateRepository
        self.operationQueue = operationQueue
    }
}

extension TattooPhotoPreviewInteractor: TattooPhotoViewInteractorInputProtocol {
    func setup() {
        do {
            let photoPreviewData = try Data(contentsOf: fileManager.preparePhotoEvidenceUrl())
            guard let photoPreview = UIImage(data: photoPreviewData) else { return }
            presenter?.didReceive(photoPreview: photoPreview)
        } catch {
            presenter?.didReceive(error: .photoLoading(error))
        }
    }

    func initiateUploading() {
        do {
            let files = try fileManager.completeEvidenceProviding()

            let localState = EvidenceSubmission.LocalState(
                videoName: files.videoUrl.lastPathComponent,
                photoName: files.photoUrl.lastPathComponent,
                sessionId: UUID().uuidString
            )

            let operation = localStateRepository.saveOperation({ [localState] }, { [] })

            execute(
                operation: operation,
                inOperationQueue: operationQueue,
                runningCallbackIn: .main
            ) { [weak self] result in
                switch result {
                case .success:
                    self?.presenter?.didInitiateEvidenceUploading()
                case let .failure(error):
                    self?.presenter?.didReceive(error: .evidenceUploading(error))
                }
            }
        } catch {
            presenter?.didReceive(error: .evidenceUploading(error))
        }
    }

    func discardPhotoEvidence() {
        do {
            try fileManager.forgetPhotoEvidence()
        } catch {
            presenter?.didReceive(error: .photoFile(error))
        }
    }
}
