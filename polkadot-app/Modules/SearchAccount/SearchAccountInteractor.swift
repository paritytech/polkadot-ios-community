import UIKit
import Operation_iOS
import SubstrateSdk
import ChainRegistry

final class SearchAccountInteractor {
    // MARK: Properties

    weak var presenter: SearchAccountInteractorOutputProtocol?

    private let searchUsernameFactory: SearchUsernameOperationFactory
    private let recentContactsManager: RecentContactsManaging
    private let remoteContactSearch: RemoteContactOperationMaking
    private let chatOpenResolver: ChatOpenModelResolving
    private let debouncer = Debouncer(delay: 0.5, queue: .main)
    private var searchTask: Task<Void, Never>?
    private let logger: LoggerProtocol

    // MARK: Initial methods

    init(
        searchUsernameFactory: SearchUsernameOperationFactory,
        recentContactsManager: RecentContactsManaging,
        remoteContactSearch: RemoteContactOperationMaking,
        chatOpenResolver: ChatOpenModelResolving,
        logger: LoggerProtocol
    ) {
        self.searchUsernameFactory = searchUsernameFactory
        self.recentContactsManager = recentContactsManager
        self.remoteContactSearch = remoteContactSearch
        self.chatOpenResolver = chatOpenResolver
        self.logger = logger
    }

    deinit {
        searchTask?.cancel()
    }
}

// MARK: - SearchAccountInteractorInputProtocol

extension SearchAccountInteractor: SearchAccountInteractorInputProtocol {
    func setup() {
        Task { [weak presenter, searchUsernameFactory, logger] in
            do {
                let accounts = try await searchUsernameFactory.allUsernames()
                try Task.checkCancellation()

                await presenter?.didFetchAllContacts(accounts)
            } catch {
                logger.debug("Fetch all contacts failed \(error)")
            }
        }
    }

    func subscribeToRecentContacts(for chainAsset: ChainAsset) {
        recentContactsManager.setup(self, chainAssetID: chainAsset.chainAssetId)
    }

    func searchAccount(for input: String) {
        searchTask?.cancel()

        debouncer.debounce { [weak self] in
            self?.performSearch(query: input)
        }
    }

    func resolveChat(for contact: Chat.RemoteContact) {
        Task { [weak self, chatOpenResolver] in
            do {
                let model = try await chatOpenResolver.resolveOpenModel(for: contact)
                await self?.presenter?.didResolveChat(model)
            } catch {
                await self?.presenter?.didReceiveSearchError(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - RecentContactsServiceDelegate

extension SearchAccountInteractor: RecentContactsServiceDelegate {
    func recentContactsServiceDidUpdate(recentContacts: [DataProviderChange<RecentContactModelWithUsername>]) {
        Task { [weak presenter] in
            await presenter?.didReceiveRecentContacts(recentContacts)
        }
    }

    func recentContactServiceDidFail(error: any Error) {
        logger.error(error.localizedDescription)
        Task { [weak presenter] in
            await presenter?.didReceiveRecentContacts([])
        }
    }
}

// MARK: - Private

private extension SearchAccountInteractor {
    func performSearch(query: String) {
        searchTask?.cancel()

        searchTask = Task { [weak presenter, searchUsernameFactory, remoteContactSearch, logger] in
            do {
                async let localResults = searchUsernameFactory.searchUsername(
                    for: UsernameRequestModel(prefix: query)
                )
                async let globalResults = remoteContactSearch.search(by: query).asyncExecute()

                let local = try await localResults
                let global = await (try? globalResults) ?? []

                try Task.checkCancellation()
                await presenter?.didFindContacts(local)
                await presenter?.didFindGlobalContacts(global)
            } catch {
                guard !Task.isCancelled else { return }

                logger.debug(error.localizedDescription)
                await presenter?.didReceiveSearchError(message: error.localizedDescription)
            }
        }
    }
}
