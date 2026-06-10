import Foundation
import PolkadotUI
import UIKitExt

protocol ContactsListViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: ContactsListViewLayout.ViewModel)
}

protocol ContactsListPresenterProtocol: AnyObject {
    func setup()
    func viewWillAppear()
    func viewWillDisappear()
    func showSearchContact()
    func openChat(contactIdentifier: String)
    func showIncomingRequests()
}

protocol ContactsListInteractorInputProtocol: AnyObject {
    func setup()
    func notifyViewAppeared()
    func notifyViewDisappeared()
    func entryRoute(for model: ChatOpenModel) async -> ChatExtensionEntryRoute
}

@MainActor
protocol ContactsListInteractorOutputProtocol: AnyObject {
    func didReceive(model: ChatListModel)
    func didReceive(error: Error)
}

protocol ContactsListWireframeProtocol: AlertPresentable, ErrorPresentable {
    func showSearchContact(from view: ContactsListViewProtocol?)
    func showChat(from view: ContactsListViewProtocol?, for model: ChatOpenModel)
    func open(url: URL)
    func showIncomingRequests(from view: ContactsListViewProtocol?)
}
