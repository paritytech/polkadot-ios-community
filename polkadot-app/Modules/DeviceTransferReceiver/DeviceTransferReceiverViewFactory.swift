import Foundation

@MainActor
enum DeviceTransferReceiverViewFactory {
    static func createView(observer: RootStateObserving) -> DeviceTransferReceiverViewProtocol {
        let statusStore = InstallationStatusStore(logger: Logger.shared)
        let interactor = DeviceTransferReceiverInteractor(
            servicesFactory: DeviceTransferServicesFactory(statusStore: statusStore, logger: Logger.shared),
            statusStore: statusStore,
            screenSleep: OperatingSystemMediator(),
            logger: Logger.shared
        )
        let wireframe = DeviceTransferReceiverWireframe(observer: observer)
        let presenter = DeviceTransferReceiverPresenter(interactor: interactor, wireframe: wireframe)
        let view = DeviceTransferReceiverViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
