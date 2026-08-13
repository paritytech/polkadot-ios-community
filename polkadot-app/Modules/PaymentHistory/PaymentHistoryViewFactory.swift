import Foundation

enum PaymentHistoryViewFactory {
    @MainActor
    static func createView() -> PaymentHistoryViewProtocol? {
        let historyStore = W3sPaymentHistoryCoreDataStore(
            storageFacade: UserDataStorageFacade.shared
        )
        let interactor = PaymentHistoryInteractor(historyStore: historyStore)
        let wireframe = PaymentHistoryWireframe()
        let presenter = PaymentHistoryPresenter(interactor: interactor, wireframe: wireframe)
        let view = PaymentHistoryViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
