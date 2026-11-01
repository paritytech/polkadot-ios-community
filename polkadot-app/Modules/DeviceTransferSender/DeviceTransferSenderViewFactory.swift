import Foundation

@MainActor
enum DeviceTransferSenderViewFactory {
    static func createView(
        request: DeviceTransferRequest,
        observer: RootStateObserving
    ) -> DeviceTransferSenderViewProtocol {
        let interactor = DeviceTransferSenderInteractor()
        let wireframe = DeviceTransferSenderWireframe(observer: observer)
        let presenter = DeviceTransferSenderPresenter(request: request, interactor: interactor, wireframe: wireframe)
        let view = DeviceTransferSenderViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
