import Foundation

final class InstallationCheckPresenter {
    weak var view: InstallationCheckViewProtocol?
    let wireframe: InstallationCheckWireframeProtocol
    let interactor: InstallationCheckInteractorInputProtocol

    init(interactor: InstallationCheckInteractorInputProtocol, wireframe: InstallationCheckWireframeProtocol) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension InstallationCheckPresenter: InstallationCheckPresenterProtocol {
    func setup() {
        interactor.start()
    }
}

extension InstallationCheckPresenter: InstallationCheckInteractorOutputProtocol {
    func didSettleStatus() {
        wireframe.complete()
    }
}
