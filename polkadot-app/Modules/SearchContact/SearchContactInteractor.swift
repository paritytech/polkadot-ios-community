import UIKit
import Operation_iOS
import SubstrateSdk

final class SearchContactInteractor {
    weak var presenter: SearchContactInteractorOutputProtocol?

    private let searchApi: RemoteContactOperationMaking
    private let chatRepositoryFactory: ChatRepositoryMaking
    private let ownAccountId: AccountId

    private let debouncer = Debouncer(delay: 0.3, queue: .main)
    private var searchTask: Task<Void, Never>?
    private var latestQuery: String = ""

    init(
        ownAccountId: AccountId,
        searchApi: RemoteContactOperationMaking = RemoteContactOperationFactory(),
        chatRepositoryFactory: ChatRepositoryMaking = ChatRepositoryFactory()
    ) {
        self.ownAccountId = ownAccountId
        self.searchApi = searchApi
        self.chatRepositoryFactory = chatRepositoryFactory
    }

    deinit {
        cancelCurrentSearch()
    }
}

extension SearchContactInteractor: SearchContactInteractorInputProtocol {
    func search(username: String) {
        guard !username.isEmpty else {
            debouncer.cancel()
            cancelCurrentSearch()

            searchTask = Task { [weak self] in
                await self?.presenter?.didReceive(searchResults: [], for: username)
            }
            return
        }

        latestQuery = username
        debouncer.debounce { [weak self] in
            self?.performSearch(query: username)
        }
    }

    func decide(on contact: Chat.RemoteContact) {
        let chatRepository = chatRepositoryFactory.createRepository(
            forFilter: .contact(for: contact.accountId)
        )

        Task { [weak self] in
            do {
                let chats = try await chatRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()

                let openModel: ChatOpenModel
                if let chat = chats.first {
                    openModel = .existingChat(chat.chatId)
                } else {
                    let newRequest = ChatOpenModel.NewRequest(remoteContact: contact, ownKeyId: Chat.Contact.Own.main())
                    openModel = .newRequest(newRequest)
                }
                await self?.presenter?.didReceive(resolution: openModel)
            } catch {
                await self?.presenter?.didReceive(error: error)
            }
        }
    }
}

private extension SearchContactInteractor {
    func cancelCurrentSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

    func performSearch(query: String) {
        cancelCurrentSearch()

        searchTask = Task { [weak presenter, searchApi, ownAccountId] in
            do {
                if let accountId = try? query.toAccountId(),
                   accountId != ownAccountId,
                   let account = try? await searchApi.fetch(by: accountId) {
                    try Task.checkCancellation()
                    await presenter?.didReceive(searchResults: [account], for: query)
                    return
                }

                let contacts = try await searchApi.search(by: query).asyncExecute()

                let matchedContacts = contacts.filter { $0.accountId != ownAccountId }

                try Task.checkCancellation()
                await presenter?.didReceive(searchResults: matchedContacts, for: query)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await presenter?.didReceive(searchError: error, for: query)
            }
        }
    }
}
