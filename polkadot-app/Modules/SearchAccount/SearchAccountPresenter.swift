import Foundation
import Foundation_iOS
import Operation_iOS
import SubstrateSdk
import ChainRegistry
import SubstrateSdkExt

@MainActor
final class SearchAccountPresenter {
    // MARK: Properties

    static let maxRecentContactsDisplay = 5

    weak var view: SearchAccountViewProtocol?
    let wireframe: SearchAccountWireframeProtocol
    let interactor: SearchAccountInteractorInputProtocol
    private let chainAsset: ChainAsset
    private let logger: LoggerProtocol
    private var addressInputViewModel = InputViewModel.createAccountInputViewModel(for: "")
    private let recipientViewModelFactory: RecipientViewModelFactoryProtocol
    private var recentContactsMap = [String: RecentContactModelWithUsername]()
    private var allContacts: [UsernameResponseModel] = []
    private var contactResults: [SearchAccountViewModel.AccountType] = []
    private var globalContacts: [AccountAddress: Chat.RemoteContact] = [:]
    private var currentQuery: String?

    init(
        interactor: SearchAccountInteractorInputProtocol,
        wireframe: SearchAccountWireframeProtocol,
        recipientViewModelFactory: RecipientViewModelFactoryProtocol,
        logger: LoggerProtocol,
        chainAsset: ChainAsset
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.recipientViewModelFactory = recipientViewModelFactory
        self.logger = logger
        self.chainAsset = chainAsset
    }

    private func provideAddressInputViewModel(_ accountType: SearchAccountViewModel.AccountType? = nil) {
        guard let view else { return }

        view.didReceive(
            SearchAccountViewModel(
                inputViewModel: SearchAccountViewModel.InputModel(
                    inputViewModel: addressInputViewModel,
                    selectedAccount: accountType
                ),
                dataType: view.viewModel.dataType
            )
        )
    }

    private func handleAccountSelection(_ accountType: SearchAccountViewModel.AccountType) {
        addressInputViewModel = InputViewModel.createAccountInputViewModel(for: accountType.title)
        provideAddressInputViewModel(accountType)
    }

    private func mapToAccountType(from model: UsernameResponseModel) -> SearchAccountViewModel.AccountType {
        .username(model.username.value, model.accountId)
    }

    private func mapToAccountType(from accountAddress: AccountAddress) -> SearchAccountViewModel.AccountType {
        .accountAddress(accountAddress)
    }

    private func isAccountAddress(_ inputText: String) -> Bool {
        guard (try? inputText.toAccountId(using: chainAsset.chain.chainFormat)) != nil else {
            logger.debug("Invalid account address format")
            return false
        }
        return true
    }

    private func updateViewModel(dataType: SearchAccountViewModel.DataType) {
        let viewModel = SearchAccountViewModel(
            inputViewModel: SearchAccountViewModel.InputModel(
                inputViewModel: addressInputViewModel
            ),
            dataType: dataType
        )
        view?.applyData(viewModel)
    }

    private func filterRecentContactsByQuery(_ query: String) -> [RecipientViewModel] {
        let lowerQuery = query.lowercased()
        let filtered = recentContactsMap.filter { _, contact in
            let usernameMatches = (contact.username?.value ?? "").lowercased().hasPrefix(lowerQuery)
            let addressMatches = (try? contact.recentContact.accountID.toAddress(
                using: chainAsset.chain.chainFormat
            ))?.lowercased().hasPrefix(lowerQuery) ?? false
            return usernameMatches || addressMatches
        }
        return recipientViewModelFactory.createRecentContacts(from: filtered)
    }

    private func dedupe(
        _ accounts: [SearchAccountViewModel.AccountType],
        against recent: [RecipientViewModel]
    ) -> [SearchAccountViewModel.AccountType] {
        let recentIds = Set(recent.compactMap { try? $0.accountType.accountAddress.toAccountId() })
        return accounts.filter { account in
            guard let accountId = try? account.accountAddress.toAccountId() else { return true }
            return !recentIds.contains(accountId)
        }
    }

    private func updateIdleViewModel() {
        let recent = recipientViewModelFactory.createRecentContacts(from: recentContactsMap)
            .prefix(Self.maxRecentContactsDisplay)
        let contacts = allContacts.map { mapToAccountType(from: $0) }
        let filtered = dedupe(contacts, against: Array(recent))

        updateViewModel(dataType: .idle(recent: Array(recent), contacts: filtered))
    }

    private func rebuildSearchResultsForCurrentQuery() {
        guard let currentQuery else { return }

        let recentMatches = filterRecentContactsByQuery(currentQuery)
        let contacts = dedupe(contactResults, against: recentMatches)

        let recentIds = Set(recentMatches.compactMap { try? $0.accountType.accountAddress.toAccountId() })
        let contactIds = Set(contacts.compactMap { try? $0.accountAddress.toAccountId() })

        let globalRows = globalContacts
            .filter { _, contact in
                !recentIds.contains(contact.accountId) && !contactIds.contains(contact.accountId)
            }
            .sorted { $0.value.username < $1.value.username }
            .map { address, contact in
                SearchAccountViewModel.AccountType.username(contact.username, address)
            }

        updateViewModel(
            dataType: .searchResults(recent: recentMatches, contacts: contacts, global: globalRows)
        )
    }
}

// MARK: - SearchAccountPresenterProtocol

extension SearchAccountPresenter: SearchAccountPresenterProtocol {
    func viewDidLoad() {
        interactor.setup()
        interactor.subscribeToRecentContacts(for: chainAsset)
        provideAddressInputViewModel()
    }

    func scanQRCode() {
        wireframe.showQRScan(from: view)
    }

    func searchAccount(_ account: String?) {
        guard
            let inputText = account?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !inputText.isEmpty
        else {
            currentQuery = nil
            contactResults = []
            globalContacts.removeAll()
            return updateIdleViewModel()
        }

        currentQuery = inputText
        contactResults = []
        globalContacts.removeAll()

        if isAccountAddress(inputText) {
            contactResults = [mapToAccountType(from: inputText)]
            rebuildSearchResultsForCurrentQuery()
        } else if inputText.count <= .maximumPrefixCount {
            rebuildSearchResultsForCurrentQuery()
            interactor.searchAccount(for: inputText.trimmingDot())
            view?.didStartLoading()
        } else {
            updateViewModel(dataType: .searchResults(recent: [], contacts: [], global: []))
        }
    }

    func selectAccount(_ cellType: SearchAccountViewController.Cell) {
        switch cellType {
        case let .globalContact(accountType):
            guard let contact = globalContacts[accountType.accountAddress] else { return }
            interactor.resolveChat(for: contact)
        case .account,
             .recentContact:
            handleAccountSelection(cellType.accountType)
            guard let recipient = try? RecipientModel(accountType: cellType.accountType) else { return }
            wireframe.showTransfer(from: view, recipient: recipient, chainAsset: chainAsset)
        }
    }

    func didEndEditingInput(_ input: String?) {
        guard
            let inputText = input?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !inputText.isEmpty
        else {
            return
        }

        let accountType: SearchAccountViewModel.AccountType = isAccountAddress(inputText) ?
            mapToAccountType(from: inputText) :
            .username(inputText, inputText)

        provideAddressInputViewModel(accountType)
    }
}

// MARK: - SearchAccountInteractorOutputProtocol

extension SearchAccountPresenter: SearchAccountInteractorOutputProtocol {
    func didFetchAllContacts(_ accounts: [UsernameResponseModel]) {
        let sorted = accounts.sorted { $0.username < $1.username }
        allContacts = sorted
        guard currentQuery == nil else { return }
        updateIdleViewModel()
    }

    func didFindContacts(_ accounts: [UsernameResponseModel]) {
        view?.didStopLoading()
        let sorted = accounts.sorted { $0.username < $1.username }
        contactResults = sorted.map { mapToAccountType(from: $0) }
        rebuildSearchResultsForCurrentQuery()
    }

    func didFindGlobalContacts(_ contacts: [Chat.RemoteContact]) {
        globalContacts = contacts.reduce(into: [AccountAddress: Chat.RemoteContact]()) { result, contact in
            guard let address = try? contact.accountId.toAddress(using: chainAsset.chain.chainFormat) else {
                return
            }
            result[address] = contact
        }
        rebuildSearchResultsForCurrentQuery()
    }

    func didResolveChat(_ model: ChatOpenModel) {
        wireframe.showChat(model)
    }

    func didReceiveSearchError(message: String?) {
        wireframe.present(
            message: message,
            title: String(localized: .Common.error),
            closeAction: String(localized: .Common.close),
            from: view
        )
    }

    func didReceiveRecentContacts(_ contacts: [DataProviderChange<RecentContactModelWithUsername>]) {
        guard !contacts.isEmpty else { return }
        recentContactsMap = contacts.mergeToDict(recentContactsMap)
        guard currentQuery == nil else { return }
        updateIdleViewModel()
    }
}

// MARK: - Constants

private extension Int {
    static let maximumPrefixCount = 32
}
