import Foundation

@MainActor
enum DeviceTransferRequestViewFactory {
    static func createView(
        request: DeviceTransferRequest,
        listener: DeviceTransferRequestListening,
        observer: RootStateObserving
    ) -> DeviceTransferRequestViewProtocol {
        let interactor = DeviceTransferRequestInteractor(
            listener: listener,
            servicesFactory: DeviceTransferServicesFactory(
                statusStore: InstallationStatusStore(logger: Logger.shared),
                logger: Logger.shared
            ),
            paymentsCounter: TransferStateCoreDataStore(storageFacade: UserDataStorageFacade.shared),
            logger: Logger.shared
        )
        let wireframe = DeviceTransferRequestWireframe(observer: observer)
        let presenter = DeviceTransferRequestPresenter(request: request, interactor: interactor, wireframe: wireframe)
        let view = DeviceTransferRequestViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        BottomSheetViewFacade.setupNonNavigatingSheet(from: view)

        return view
    }
}
