import Foundation

enum AppsListViewFactory {
    static func createView() -> AppsListViewProtocol? {
        let interactor = AppsListInteractor(
            providerFactory: ProductPermissionDataProviderFactory()
        )

        let wireframe = AppsListWireframe()

        let presenter = AppsListPresenter(
            interactor: interactor,
            wireframe: wireframe,
            viewModelFactory: AppsListViewModelFactory()
        )

        let view = AppsListViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
