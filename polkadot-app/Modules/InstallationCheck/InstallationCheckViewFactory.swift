import Foundation

enum InstallationCheckViewFactory {
    static func createView(observer: RootStateObserving) -> InstallationCheckViewProtocol {
        let interactor = InstallationCheckInteractor(
            serviceFactory: ActiveInstallationServiceFactory(
                statusStore: InstallationStatusStore(logger: Logger.shared),
                logger: Logger.shared
            ),
            logger: Logger.shared
        )
        let wireframe = InstallationCheckWireframe(observer: observer)
        let presenter = InstallationCheckPresenter(interactor: interactor, wireframe: wireframe)
        let view = InstallationCheckViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
