import PolkadotUI
import UIKitExt

protocol SearchContactViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: SearchContactViewLayout.ViewModel)
}

protocol SearchContactPresenterProtocol: AnyObject {
    func setup()
    func search(username: String)
    func didSelectContact(identifier: String)
}

protocol SearchContactInteractorInputProtocol: AnyObject {
    func search(username: String)
    func decide(on contact: Chat.RemoteContact)
}

@MainActor
protocol SearchContactInteractorOutputProtocol: AnyObject {
    func didReceive(searchResults results: [Chat.RemoteContact], for query: String)
    func didReceive(searchError error: Error, for query: String)
    func didReceive(error: Error)
    func didReceive(resolution: ChatOpenModel)
}

protocol SearchContactWireframeProtocol: AnyObject, AlertPresentable, ErrorPresentable {
    func complete(from view: SearchContactViewProtocol?, with model: ChatOpenModel)
}
