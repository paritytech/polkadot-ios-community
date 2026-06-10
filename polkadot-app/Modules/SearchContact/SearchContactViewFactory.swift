import Foundation

enum SearchContactViewFactory {
    static func createView(with model: SearchContactModel) -> SearchContactViewProtocol? {
        guard let ownAccountId = try? SelectedWallet.main.getRawPublicKey() else {
            assertionFailure()
            return nil
        }

        let interactor = SearchContactInteractor(ownAccountId: ownAccountId)
        let wireframe = SearchContactWireframe(model: model)

        let presenter = SearchContactPresenter(
            interactor: interactor,
            wireframe: wireframe
        )

        let view = SearchContactViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
