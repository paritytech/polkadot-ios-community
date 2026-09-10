import UIKit
import Operation_iOS
import SubstrateSdk

final class SearchContactInteractor {
    weak var presenter: SearchContactInteractorOutputProtocol?

    private let searchApi: RemoteContactOperationMaking
    private let chatOpenResolver: ChatOpenModelResolving
    private let ownAccountId: AccountId
    private let searchRunner = SearchRunner()
    private var searchTask: Task<Void, Never>?

    init(
        ownAccountId: AccountId,
        searchApi: RemoteContactOperationMaking = RemoteContactOperationFactory(),
        chatOpenResolver: ChatOpenModelResolving = ChatOpenModelResolver()
    ) {
        self.ownAccountId = ownAccountId
        self.searchApi = searchApi
        self.chatOpenResolver = chatOpenResolver
    }

    deinit {
        cancelSearchTask()
    }
}

extension SearchContactInteractor: SearchContactInteractorInputProtocol {
    func search(username: String) {
        cancelSearchTask()

        guard !username.isEmpty else {
            searchTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                await self?.presenter?.didReceive(searchState: .result(.contacts([])), for: username)
            }
            return
        }

        searchTask = Task { [weak presenter, searchRunner, searchApi, ownAccountId] in
            let stateStream = searchRunner.run {
                await Self.makeSearchResult(
                    for: username,
                    ownAccountId: ownAccountId,
                    searchApi: searchApi
                )
            }
            for await state in stateStream {
                guard !Task.isCancelled else { return }
                await presenter?.didReceive(searchState: state, for: username)
            }
        }
    }

    func decide(on contact: Chat.RemoteContact) {
        Task { [weak self, chatOpenResolver] in
            do {
                let openModel = try await chatOpenResolver.resolveOpenModel(for: contact)
                await self?.presenter?.didReceive(resolution: openModel)
            } catch {
                await self?.presenter?.didReceive(error: error)
            }
        }
    }
}

private extension SearchContactInteractor {
    func cancelSearchTask() {
        searchTask?.cancel()
        searchTask = nil
    }

    static func makeSearchResult(
        for query: String,
        ownAccountId: AccountId,
        searchApi: RemoteContactOperationMaking
    ) async -> SearchContactSearchResult? {
        do {
            if let accountId = try? query.toAccountId(),
               accountId != ownAccountId,
               let account = try? await searchApi.fetch(by: accountId) {
                try Task.checkCancellation()
                return .contacts([account])
            }
            let contacts = try await searchApi.search(by: query).asyncExecute()
            let matchedContacts = contacts.filter { $0.accountId != ownAccountId }
            try Task.checkCancellation()
            return .contacts(matchedContacts)
        } catch {
            guard !Task.isCancelled else { return nil }
            return .error(error)
        }
    }
}
