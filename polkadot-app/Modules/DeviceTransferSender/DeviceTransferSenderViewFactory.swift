import Foundation

@MainActor
enum DeviceTransferSenderViewFactory {
    static func createView(
        request: DeviceTransferRequest,
        observer: RootStateObserving
    ) -> DeviceTransferSenderViewProtocol {
        let issueDiagnostics = DeviceTransferIssueDiagnostics.makeDefault()
        let interactor = DeviceTransferSenderInteractor(
            servicesFactory: DeviceTransferServicesFactory(
                statusStore: InstallationStatusStore(logger: Logger.shared),
                logger: Logger.shared,
                issueDiagnostics: issueDiagnostics
            ),
            dashboardServices: DashboardServices.manager,
            screenSleep: OperatingSystemMediator(),
            settings: DeviceTransferSenderModuleSettings(setupDiagnostic: issueDiagnostics.setupFailed),
            logger: Logger.shared
        )
        let wireframe = DeviceTransferSenderWireframe(observer: observer)
        let presenter = DeviceTransferSenderPresenter(request: request, interactor: interactor, wireframe: wireframe)
        let view = DeviceTransferSenderViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
