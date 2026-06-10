import Foundation
import Operation_iOS
import Foundation_iOS
import UIKitExt

protocol SearchAccountViewProtocol: ControllerBackedProtocol {
    var viewModel: SearchAccountViewModel { get }
    func didReceive(_ viewModel: SearchAccountViewModel)
    func applyData(_ viewModel: SearchAccountViewModel)
    func didStartLoading()
    func didStopLoading()
}

protocol SearchAccountPresenterProtocol: AnyObject {
    func viewDidLoad()
    func scanAddress()
    func didEndEditingInput(_ input: String?)
    func searchAccount(_ account: String?)
    func selectAccount(_ cellType: SearchAccountViewController.Cell)
}

protocol SearchAccountInteractorInputProtocol: AnyObject {
    func setup()
    func subscribeToRecentContacts(for chainAsset: ChainAsset)
    func searchAccount(for input: String)
}

@MainActor
protocol SearchAccountInteractorOutputProtocol: AnyObject {
    func didFetchAllContacts(_ accounts: [UsernameResponseModel])
    func didFindSearchResults(_ accounts: [UsernameResponseModel])
    func didReceiveSearchError(message: String?)
    func didReceiveRecentContacts(_ contacts: [DataProviderChange<RecentContactModelWithUsername>])
}

protocol SearchAccountWireframeProtocol: AnyObject, ScanAddressPresentable, AlertPresentable {
    func showTransfer(
        from view: SearchAccountViewProtocol?,
        recipient: RecipientModel,
        chainAsset: ChainAsset
    )
}
