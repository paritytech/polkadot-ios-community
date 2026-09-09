import UIKit
import Operation_iOS
import SubstrateSdk
import SubstrateSdkExt
import ChainRegistry
import Foundation_iOS
import os

final class SearchAccountInteractor {
    // MARK: Properties

    weak var presenter: SearchAccountInteractorOutputProtocol?

    private let searchUsernameFactory: SearchUsernameOperationFactory
    private let recentContactsManager: RecentContactsManaging
    private let remoteContactSearch: RemoteContactOperationMaking
    private let chatOpenResolver: ChatOpenModelResolving
    private let debouncer = Debouncer(delay: 0.5, queue: .main)
    private var searchTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private let logger: LoggerProtocol
    private let chainAsset: ChainAsset
    private let stateLock: OSAllocatedUnfairLock<State>

    private static let maximumPrefixCount = 32

    // MARK: Initial methods

    init(
        searchUsernameFactory: SearchUsernameOperationFactory,
        recentContactsManager: RecentContactsManaging,
        remoteContactSearch: RemoteContactOperationMaking,
        chatOpenResolver: ChatOpenModelResolving,
        chainAsset: ChainAsset,
        logger: LoggerProtocol
    ) {
        self.searchUsernameFactory = searchUsernameFactory
        self.recentContactsManager = recentContactsManager
        self.remoteContactSearch = remoteContactSearch
        self.chatOpenResolver = chatOpenResolver
        self.chainAsset = chainAsset
        self.logger = logger
        stateLock = OSAllocatedUnfairLock(initialState: State(chainFormat: chainAsset.chain.chainFormat))
    }

    deinit {
        searchTask?.cancel()
        setupTask?.cancel()
    }
}

// MARK: - SearchAccountInteractorInputProtocol

extension SearchAccountInteractor: SearchAccountInteractorInputProtocol {
    func setup() {
        setupTask?.cancel()

        setupTask = Task { [weak self, searchUsernameFactory, logger] in
            do {
                let accounts = try await searchUsernameFactory.allUsernames()
                try Task.checkCancellation()

                guard let self else { return }

                let snapshot: State? = stateLock.withLock { state in
                    state.allContacts = accounts.sorted { $0.username < $1.username }
                    guard state.query == nil else { return nil }
                    return state
                }

                guard let snapshot else { return }

                emit(snapshot.makeIdleResult())
            } catch {
                logger.debug("Fetch all contacts failed \(error)")
            }
        }
    }

    func subscribeToRecentContacts() {
        recentContactsManager.setup(self, chainAssetID: chainAsset.chainAssetId)
    }

    func searchAccount(for input: String?) {
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let query = trimmed, !query.isEmpty else {
            let snapshot = resetResults(for: nil)
            emit(snapshot.makeIdleResult())
            return
        }

        let isValidAddress = (try? query.toAccountId(using: chainAsset.chain.chainFormat)) != nil

        guard isValidAddress || query.count <= Self.maximumPrefixCount else {
            resetResults(for: query)
            emit(
                SearchAccountResult(
                    query: query,
                    loader: .unchanged,
                    recent: [],
                    contacts: [],
                    global: []
                )
            )
            return
        }

        let snapshot = resetResults(for: query)
        let addressRow = SearchAccountResult.Contact(username: nil, address: query)

        emit(
            snapshot.makeSearchResult(
                query: query,
                matched: isValidAddress ? [addressRow] : [],
                loader: isValidAddress ? .unchanged : .start
            )
        )

        guard !isValidAddress else { return }

        searchTask?.cancel()
        debouncer.debounce { [weak self] in
            self?.performSearch(query: query)
        }
    }

    func resolveChat(for address: AccountAddress) {
        guard let accountId = try? address.toAccountId(using: chainAsset.chain.chainFormat) else { return }

        let contact: Chat.RemoteContact? = stateLock.withLock { state in
            state.globalContacts[accountId]
        }

        guard let contact else { return }

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
        guard !recentContacts.isEmpty else { return }

        let snapshot: State? = stateLock.withLock { state in
            state.recentContactsMap = recentContacts.mergeToDict(state.recentContactsMap)
            guard state.query == nil else { return nil }
            return state
        }

        guard let snapshot else { return }

        emit(snapshot.makeIdleResult())
    }

    func recentContactServiceDidFail(error: any Error) {
        logger.error(error.localizedDescription)
    }
}

// MARK: - Private

private extension SearchAccountInteractor {
    func performSearch(query: String) {
        searchTask?.cancel()

        searchTask = Task { [weak self, searchUsernameFactory, remoteContactSearch, logger] in
            do {
                async let localResults = searchUsernameFactory.searchUsername(
                    for: UsernameRequestModel(prefix: query.trimmingDot())
                )
                async let globalResults = remoteContactSearch.search(by: query).asyncExecute()

                let local = try await localResults
                let global = await (try? globalResults) ?? []

                try Task.checkCancellation()

                guard let self else { return }

                let matched = local
                    .sorted { $0.username < $1.username }
                    .map { SearchAccountResult.Contact(
                        username: $0.username.value,
                        address: $0.accountId
                    ) }

                let snapshot: State? = stateLock.withLock { state in
                    guard state.query == query else { return nil }

                    state.globalContacts = global.reduce(into: [:]) { result, contact in
                        result[contact.accountId] = contact
                    }

                    return state
                }

                guard let snapshot else { return }

                emit(
                    snapshot.makeSearchResult(
                        query: query,
                        matched: matched,
                        loader: .stop
                    )
                )
            } catch {
                guard !Task.isCancelled else { return }

                logger.debug(error.localizedDescription)
                await self?.presenter?.didReceiveSearchError(message: error.localizedDescription)
            }
        }
    }

    private func emit(_ result: SearchAccountResult) {
        let isCurrent = stateLock.withLock { $0.query == result.query }

        guard isCurrent else { return }

        Task { [weak presenter] in
            await presenter?.didReceive(result)
        }
    }

    /// Latches the new query and drops the global results of the previous one, returning a snapshot to compose from.
    @discardableResult
    private func resetResults(for query: String?) -> State {
        stateLock.withLock { state in
            state.query = query
            state.globalContacts.removeAll()
            return state
        }
    }
}

extension SearchAccountInteractor {
    private struct State {
        let chainFormat: ChainFormat
        var recentContactsMap = [String: RecentContactModelWithUsername]()
        var allContacts: [UsernameResponseModel] = []
        var globalContacts: [AccountId: Chat.RemoteContact] = [:]
        var query: String?

        private static let maxRecentContactsDisplay = 5

        func validatedRecents() -> [RecentContactModelWithUsername] {
            recentContactsMap.values
                .sorted { $0.recentContact.lastUsed > $1.recentContact.lastUsed }
                .filter { $0.chainAsset != nil }
        }

        func makeIdleResult() -> SearchAccountResult {
            let recent = Array(validatedRecents().prefix(State.maxRecentContactsDisplay))
            let recentIds = Set(recent.map(\.recentContact.accountID))

            let allContacts = allContacts
                .map { SearchAccountResult.Contact(username: $0.username.value, address: $0.accountId) }

            return SearchAccountResult(
                query: nil,
                loader: .unchanged,
                recent: recent,
                contacts: State.dedupe(allContacts, excluding: recentIds).contacts,
                global: []
            )
        }

        func makeSearchResult(
            query: String,
            matched: [SearchAccountResult.Contact],
            loader: SearchAccountResult.LoaderChange
        ) -> SearchAccountResult {
            let recentMatches = filterRecents(
                validatedRecents(),
                matching: query
            )
            let recentIds = Set(recentMatches.map(\.recentContact.accountID))
            let deduped = State.dedupe(matched, excluding: recentIds)

            let globalRows = globalContacts.values
                .sorted { $0.username < $1.username }
                .filter { contact in
                    !recentIds.contains(contact.accountId) && !deduped.accountIds.contains(contact.accountId)
                }
                .compactMap { (contact: Chat.RemoteContact) -> SearchAccountResult.Contact? in
                    guard let address = try? contact.accountId.toAddress(using: chainFormat) else {
                        return nil
                    }
                    return SearchAccountResult.Contact(username: contact.username, address: address)
                }

            return SearchAccountResult(
                query: query,
                loader: loader,
                recent: recentMatches,
                contacts: deduped.contacts,
                global: globalRows
            )
        }

        func filterRecents(
            _ recents: [RecentContactModelWithUsername],
            matching query: String
        ) -> [RecentContactModelWithUsername] {
            let lowercasedQuery = query.lowercased()

            return recents.filter { contact in
                let username = contact.username?.value.lowercased() ?? ""

                guard !username.hasPrefix(lowercasedQuery) else { return true }

                let address = try? contact.recentContact.accountID.toAddress(using: chainFormat)

                return address?.lowercased().hasPrefix(lowercasedQuery) ?? false
            }
        }

        /// Drops contacts already present in `excludedIds`, returning the survivors and their ids.
        /// A contact whose address cannot be converted stays: it cannot be proven a duplicate.
        static func dedupe(
            _ contacts: [SearchAccountResult.Contact],
            excluding excludedIds: Set<AccountId>
        ) -> (contacts: [SearchAccountResult.Contact], accountIds: Set<AccountId>) {
            var kept: [SearchAccountResult.Contact] = []
            var keptIds: Set<AccountId> = []

            for contact in contacts {
                guard let accountId = try? contact.address.toAccountId() else {
                    kept.append(contact)
                    continue
                }

                guard !excludedIds.contains(accountId) else { continue }

                kept.append(contact)
                keptIds.insert(accountId)
            }

            return (kept, keptIds)
        }
    }
}
