import UIKit

final class LocalAuthInteractor {
    weak var presenter: LocalAuthInteractorOutputProtocol?

    let deviceAuth: DeviceAuthProtocol

    init(deviceAuth: DeviceAuthProtocol) {
        self.deviceAuth = deviceAuth
    }
}

extension LocalAuthInteractor: LocalAuthInteractorInputProtocol {
    func startAuth(with reason: String) {
        guard deviceAuth.isAvailable else {
            presenter?.didFailedAuth(with: .notAvailable)
            return
        }

        deviceAuth.authenticate(
            localizedReason: reason,
            completionQueue: .main
        ) { [weak self] result in
            switch result {
            case let .success(authorized):
                if authorized {
                    self?.presenter?.didCompleteAuth()
                } else {
                    self?.presenter?.didInterruptAuth()
                }
            case let .failure(error):
                self?.presenter?.didFailedAuth(with: error)
            }
        }
    }
}
