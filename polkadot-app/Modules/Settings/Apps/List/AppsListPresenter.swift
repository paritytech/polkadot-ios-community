import Foundation
import PolkadotUI
import Products

final class AppsListPresenter {
    weak var view: AppsListViewProtocol?

    private let wireframe: AppsListWireframeProtocol
    private let interactor: AppsListInteractorInputProtocol
    private let viewModelFactory: AppsListViewModelMaking

    init(
        interactor: AppsListInteractorInputProtocol,
        wireframe: AppsListWireframeProtocol,
        viewModelFactory: AppsListViewModelMaking
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelFactory = viewModelFactory
    }
}

extension AppsListPresenter: AppsListPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func selectApp(_ item: AppsListViewLayout.Item) {
        wireframe.showAppDetail(productId: item.id, from: view)
    }
}

extension AppsListPresenter: AppsListInteractorOutputProtocol {
    func didReceive(productIds: [ProductId]) {
        let items = viewModelFactory.createItems(from: productIds)
        view?.didReceive(items: items)
    }
}
