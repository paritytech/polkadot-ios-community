import Foundation
import PolkadotUI
import UIKit
import DesignSystem
import SubstrateSdk

final class SearchContactPresenter {
    weak var view: SearchContactViewProtocol?
    let wireframe: SearchContactWireframeProtocol
    let interactor: SearchContactInteractorInputProtocol

    private var contacts: [Chat.RemoteContact] = []
    private var query: String = ""
    private var queryFailed: Bool = false

    init(
        interactor: SearchContactInteractorInputProtocol,
        wireframe: SearchContactWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension SearchContactPresenter: SearchContactPresenterProtocol {
    func setup() {
        provideViewModel()
    }

    func search(username: String) {
        interactor.search(username: username)
    }

    func didSelectContact(identifier: String) {
        guard let contact = contacts.first(where: { $0.username == identifier }) else {
            return
        }
        interactor.decide(on: contact)
    }
}

extension SearchContactPresenter: SearchContactInteractorOutputProtocol {
    func didReceive(searchResults results: [Chat.RemoteContact], for query: String) {
        contacts = results.sorted { Username(value: $0.username) < Username(value: $1.username) }
        self.query = query
        queryFailed = false

        provideViewModel()
    }

    func didReceive(searchError _: Error, for query: String) {
        contacts = []
        self.query = query
        queryFailed = true

        provideViewModel()
    }

    func didReceive(error: any Error) {
        _ = wireframe.present(error: error, from: view)
    }

    func didReceive(resolution: ChatOpenModel) {
        wireframe.complete(from: view, with: resolution)
    }
}

private extension SearchContactPresenter {
    func provideViewModel() {
        let showHint = !queryFailed && contacts.isEmpty && query.isEmpty

        // TODO: Add Highlight for username + move to factory OR move logic into ui level
        let searchFailReason: NSAttributedString?
        if queryFailed || (!query.isEmpty && contacts.isEmpty) {
            let searchFailedString = String(localized: .searchContactNoSuchUsername(username: query))
            var attributes = LabelStyle.title16SemiBold().attributes(for: .center)
            attributes[.foregroundColor] = UIColor.fgSecondary
            searchFailReason = NSAttributedString(
                string: searchFailedString,
                attributes: attributes
            )
        } else {
            searchFailReason = nil
        }

        let viewModel = SearchContactViewLayout.ViewModel(
            contactsById: contacts.map { contact in
                let prefix = String(contact.username.prefix(1))
                let avatarViewModel = AvatarViewModel.colored(
                    text: prefix,
                    colorSeed: contact.accountId.toHex()
                )
                return SearchContactListConfiguration(
                    userName: contact.username,
                    avatarViewModel: avatarViewModel
                )
            }
            .identified { $0.userName },
            showHint: showHint,
            searchFailReason: searchFailReason
        )
        view?.didReceive(viewModel: viewModel)
    }
}
