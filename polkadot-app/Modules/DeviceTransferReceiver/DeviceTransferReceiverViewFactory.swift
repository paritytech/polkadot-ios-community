import Foundation
import Operation_iOS
import Keystore_iOS

@MainActor
enum DeviceTransferReceiverViewFactory {
    static func createView() -> DeviceTransferReceiverViewProtocol? {
        let interactor = DeviceTransferReceiverInteractor()

        let wireframe = DeviceTransferReceiverWireframe()

        let presenter = DeviceTransferReceiverPresenter(interactor: interactor, wireframe: wireframe)

        let view = DeviceTransferReceiverViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
