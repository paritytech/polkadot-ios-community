import Testing
import SubstrateSdk
import Foundation
import AsyncExtensions
import Operation_iOS
import SDKLogger
import NovaCrypto
@testable import polkadot_app

struct AccountSearchProviderTests {
    // MARK: - Routing: empty/nil query

    @Test("Empty query uses allContacts() and skips global search")
    func emptyQueryUsesAllContacts() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: "")

        #expect(localSearch.didRequestAllContacts)
        #expect(localSearch.receivedUsernamePrefix == nil)
        #expect(localSearch.receivedAccountId == nil)
        #expect(remoteSearch.receivedSearchQuery == nil)
        #expect(remoteSearch.receivedFetchAccountId == nil)
    }

    @Test("Nil query uses allContacts() and skips global search")
    func nilQueryUsesAllContacts() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: nil)

        #expect(localSearch.didRequestAllContacts)
        #expect(localSearch.receivedUsernamePrefix == nil)
        #expect(localSearch.receivedAccountId == nil)
        #expect(remoteSearch.receivedSearchQuery == nil)
    }

    // MARK: - Routing: non-address query

    @Test("Non-address query uses searchContacts() and global search()")
    func nonAddressQueryUsesSearchContacts() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: "alice")

        #expect(localSearch.receivedUsernamePrefix == "alice")
        #expect(localSearch.receivedAccountId == nil)
        #expect(!localSearch.didRequestAllContacts)
        #expect(remoteSearch.receivedSearchQuery == "alice")
    }

    // MARK: - Routing: valid SS58 address

    @Test("Valid SS58 address uses contact() and fetch(), not searchContacts()")
    func validAddressUsesContactAndFetch() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)
        let targetAccountId = try Data.randomOrError(of: 32)
        let address = try SS58AddressFactory().address(fromAccountId: targetAccountId, type: 0)

        // Set fetchResult so fetch(by:) succeeds and search() is not called as fallback
        remoteSearch.fetchResult = try makeRemoteContact(accountId: targetAccountId, username: "found")

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: address)

        #expect(localSearch.receivedAccountId == targetAccountId)
        #expect(localSearch.receivedUsernamePrefix == nil)
        #expect(!localSearch.didRequestAllContacts)
        #expect(remoteSearch.receivedFetchAccountId == targetAccountId)
        #expect(remoteSearch.receivedSearchQuery == nil)
    }

    // MARK: - String normalization: trimmingDot

    @Test("Query with .dot suffix is trimmed before lookup")
    func trimmingDotRemovesSuffix() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: "alice.dot")

        #expect(localSearch.receivedUsernamePrefix == "alice")
        #expect(remoteSearch.receivedSearchQuery == "alice")
    }

    @Test("Interior .dot is preserved when normalizing the query")
    func trimmingDotPreservesInteriorMatch() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: "alice.dotty")

        #expect(localSearch.receivedUsernamePrefix == "alice.dotty")
        #expect(remoteSearch.receivedSearchQuery == "alice.dotty")
    }

    // MARK: - Filtering: blocked contacts

    @Test("Blocked contacts are filtered from results")
    func blockedContactsFiltered() async throws {
        let blockedContact = try makeContact(
            accountId: Data.randomOrError(of: 32),
            username: "blocked_user",
            isBlocked: true
        )
        let allowedContact = try makeContact(
            accountId: Data.randomOrError(of: 32),
            username: "allowed_user",
            isBlocked: false
        )

        let localSearch = MockLocalContactSearch()
        localSearch.contacts = [blockedContact, allowedContact]

        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: nil)

        #expect(result.contacts.count == 1)
        #expect(result.contacts[0].username?.value == "allowed_user")
    }

    @Test("Blocked account returned only by remote search is excluded from global")
    func blockedAccountFromRemoteSearchExcluded() async throws {
        let blockedAccountId = try Data.randomOrError(of: 32)
        let blockedContact = makeContact(
            accountId: blockedAccountId,
            username: "blocked_remote",
            isBlocked: true
        )

        // The blocked contact is known locally (so blockedContacts() returns it)
        let localSearch = MockLocalContactSearch()
        localSearch.contacts = [blockedContact]

        // Remote search returns the same blocked contact
        let remoteContactWithBlockedId = try makeRemoteContact(
            accountId: blockedAccountId,
            username: "blocked_remote"
        )

        let remoteSearch = MockRemoteContactOperationFactory()
        remoteSearch.searchResult = [remoteContactWithBlockedId]

        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        // Search with a query that won't match "blocked_remote" locally
        let result = try await provider.search(query: "xyz")

        // Should not contain the blocked account in global results
        #expect(result.global.allSatisfy { $0.accountId != blockedAccountId })
    }

    // MARK: - Filtering: own account id

    @Test("Own account id is excluded from results")
    func ownAccountIdExcluded() async throws {
        let ownAccountId = try Data.randomOrError(of: 32)
        let otherAccountId = try Data.randomOrError(of: 32)

        let ownContact = makeContact(accountId: ownAccountId, username: "own")
        let otherContact = makeContact(accountId: otherAccountId, username: "other")

        let localSearch = MockLocalContactSearch()
        localSearch.contacts = [ownContact, otherContact]

        let remoteSearch = MockRemoteContactOperationFactory()

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: nil)

        #expect(result.contacts.count == 1)
        #expect(result.contacts[0].username?.value == "other")
    }

    // MARK: - Failure handling: global search failure

    @Test("Global search failure is tolerated, returns contacts without global section")
    func globalSearchFailureNotPropagated() async throws {
        let localSearch = MockLocalContactSearch()
        let contact = try makeContact(accountId: Data.randomOrError(of: 32), username: "local_user")
        localSearch.contacts = [contact]

        let remoteSearch = MockRemoteContactOperationFactory()
        remoteSearch.searchError = AccountSearchTestError.lookupFailed

        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: "search")

        #expect(result.contacts.count == 1)
        #expect(result.global.isEmpty)
    }

    // MARK: - Recents stream updates

    @Test("Recents stream updates trigger sourcesChanged and appear in results")
    func recentsStreamUpdatesAppear() async throws {
        let (recentsStream, continuation) = AsyncStream<[SearchRow<Int>]>.makeStream()

        let recentId = try Data.randomOrError(of: 32)
        let recentRow = SearchRow(
            accountId: recentId,
            username: Username(value: "recent_user"),
            matchTerms: ["recent_user"],
            payload: 0
        )

        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { recentsStream.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        var sourcesChangedIterator = provider.sourcesChanged().makeAsyncIterator()
        provider.setup()

        continuation.yield([])
        _ = try await sourcesChangedIterator.next()

        continuation.yield([recentRow])
        _ = try await sourcesChangedIterator.next()

        let result = try await provider.search(query: nil)

        #expect(result.recent.count == 1)
        #expect(result.recent[0].username?.value == "recent_user")

        continuation.finish()
    }

    // MARK: - Remote contact fetch by id

    @Test("Remote contact fetch by valid address returns in global section")
    func remoteContactFetchByAddressReturns() async throws {
        let targetAccountId = try Data.randomOrError(of: 32)
        let address = try SS58AddressFactory().address(fromAccountId: targetAccountId, type: 0)

        let remoteContact = try makeRemoteContact(
            accountId: targetAccountId,
            username: "remote_user"
        )

        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        remoteSearch.fetchResult = remoteContact

        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: address)

        #expect(result.global.count == 1)
        #expect(result.global[0].username?.value == "remote_user")
    }

    // MARK: - Global search returns results

    @Test("Global search with non-address query returns results in global section")
    func globalSearchReturnsResults() async throws {
        let remoteContact = try makeRemoteContact(
            accountId: Data.randomOrError(of: 32),
            username: "search_result"
        )

        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        remoteSearch.searchResult = [remoteContact]

        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: "search")

        #expect(result.global.count == 1)
        #expect(result.global[0].username?.value == "search_result")
    }

    // MARK: - Phased search

    @Test("Non-empty query yields a pending phase and then a loaded phase")
    func queryYieldsPendingThenLoadedPhase() async throws {
        let context = try await makeQueryContext()
        let phases = try await collectPhases(from: context.provider, query: "alice")

        #expect(phases.count == 2)

        let pending = try #require(phases.first)
        #expect(pending.globalOutcome == .pending)
        #expect(pending.recent.count == 1)
        #expect(pending.contacts.count == 1)
        #expect(pending.global.isEmpty)

        let loaded = try #require(phases.last)
        #expect(loaded.globalOutcome == .loaded)
        #expect(loaded.recent.count == 1)
        #expect(loaded.contacts.count == 1)
        #expect(loaded.global.count == 1)
    }

    @Test("Global failure yields a failed phase keeping recent and contacts")
    func globalFailureYieldsFailedPhase() async throws {
        let context = try await makeQueryContext(globalFails: true)
        let phases = try await collectPhases(from: context.provider, query: "alice")

        #expect(phases.count == 2)

        let failed = try #require(phases.last)
        #expect(failed.globalOutcome == .failed)
        #expect(failed.global.isEmpty)
        #expect(failed.recent.count == 1)
        #expect(failed.contacts.count == 1)
    }

    @Test("Empty query yields a single loaded phase without global results")
    func emptyQueryYieldsSingleLoadedPhase() async throws {
        let context = try await makeQueryContext()
        let phases = try await collectPhases(from: context.provider, query: "")

        #expect(phases.count == 1)
        #expect(phases[0].globalOutcome == .loaded)
        #expect(phases[0].global.isEmpty)
        #expect(context.remoteSearch.receivedSearchQuery == nil)
    }

    @Test("Nil query yields a single loaded phase without global results")
    func nilQueryYieldsSingleLoadedPhase() async throws {
        let context = try await makeQueryContext()
        let phases = try await collectPhases(from: context.provider, query: nil)

        #expect(phases.count == 1)
        #expect(phases[0].globalOutcome == .loaded)
        #expect(phases[0].global.isEmpty)
        #expect(context.remoteSearch.receivedSearchQuery == nil)
    }

    @Test("Local contacts failure finishes the stream with the thrown error")
    func contactsFailureFinishesStreamWithError() async throws {
        let context = try await makeQueryContext()
        context.localSearch.contactsError = AccountSearchTestError.lookupFailed

        await #expect(throws: (any Error).self) {
            _ = try await collectPhases(from: context.provider, query: "alice")
        }

        await #expect(throws: (any Error).self) {
            _ = try await context.provider.search(query: "alice")
        }
    }

    @Test("Blocked contacts failure finishes the stream with the thrown error")
    func blockedFailureFinishesStreamWithError() async throws {
        let context = try await makeQueryContext()
        context.localSearch.blockedContactsError = AccountSearchTestError.lookupFailed

        await #expect(throws: (any Error).self) {
            _ = try await collectPhases(from: context.provider, query: "alice")
        }
    }

    @Test("Awaited search returns the last phase of a non-empty query")
    func awaitedSearchReturnsLastPhase() async throws {
        let context = try await makeQueryContext()
        let result = try await context.provider.search(query: "alice")

        #expect(result.globalOutcome == .loaded)
        #expect(result.global.count == 1)
        #expect(result.contacts.count == 1)
        #expect(result.recent.count == 1)
    }

    @Test("Awaited search returns the single loaded phase of an empty query")
    func awaitedSearchReturnsEmptyQueryPhase() async throws {
        let context = try await makeQueryContext()
        let result = try await context.provider.search(query: "")

        #expect(result.globalOutcome == .loaded)
        #expect(result.global.isEmpty)
    }

    @Test("Awaited search returns the failed phase when the global lookup fails")
    func awaitedSearchReturnsFailedPhase() async throws {
        let context = try await makeQueryContext(globalFails: true)
        let result = try await context.provider.search(query: "alice")

        #expect(result.globalOutcome == .failed)
        #expect(result.global.isEmpty)
        #expect(result.contacts.count == 1)
    }

    // MARK: - Cancellation

    @Test("A cancelled global lookup finishes after the pending phase without a failed phase")
    func cancelledGlobalLookupYieldsNoFailedPhase() async throws {
        let context = try await makeQueryContext()
        context.remoteSearch.fetchError = CancellationError()

        let address = try SS58AddressFactory().address(fromAccountId: Data.randomOrError(of: 32), type: 0)

        let phases = try await collectPhases(from: context.provider, query: address)

        #expect(phases.count == 1)
        #expect(!phases.contains { $0.globalOutcome == .failed })

        let pending = try #require(phases.first)
        #expect(pending.globalOutcome == .pending)

        let result = try await context.provider.search(query: address)
        #expect(result.globalOutcome == .pending)
    }

    @Test("Cancelling while the global lookup is in flight yields no failed phase")
    func cancellingDuringGlobalLookupYieldsNoFailedPhase() async throws {
        let context = try await makeQueryContext()
        let gate = RemoteFetchGate()
        context.remoteSearch.fetchGate = gate
        context.remoteSearch.fetchError = AccountSearchTestError.lookupFailed

        let address = try SS58AddressFactory().address(fromAccountId: Data.randomOrError(of: 32), type: 0)

        let collector = Task { try await collectPhases(from: context.provider, query: address) }

        await gate.waitUntilEntered()
        collector.cancel()
        gate.open()

        let phases = try await collector.value

        #expect(phases.count <= 1)
        #expect(!phases.contains { $0.globalOutcome == .failed })
    }
}

private enum AccountSearchTestError: Error {
    case lookupFailed
}

// MARK: - Phased search helpers

private struct QueryContext {
    let provider: AccountSearchProvider<Int>
    let localSearch: MockLocalContactSearch
    let remoteSearch: MockRemoteContactOperationFactory
}

/// Seeds one recent row, one local contact and one remote match, all matching the "alice" prefix.
private func makeQueryContext(globalFails: Bool = false) async throws -> QueryContext {
    let localSearch = MockLocalContactSearch()
    localSearch.contacts = try [makeContact(accountId: Data.randomOrError(of: 32), username: "alice_local")]

    let remoteSearch = MockRemoteContactOperationFactory()
    if globalFails {
        remoteSearch.searchError = AccountSearchTestError.lookupFailed
    } else {
        remoteSearch.searchResult = try [
            makeRemoteContact(accountId: Data.randomOrError(of: 32), username: "alice_remote")
        ]
    }

    let recentRow = try SearchRow(
        accountId: Data.randomOrError(of: 32),
        username: Username(value: "alice_recent"),
        matchTerms: ["alice_recent"],
        payload: 0
    )

    let (recentsStream, continuation) = AsyncStream<[SearchRow<Int>]>.makeStream()
    let provider = try AccountSearchProvider<Int>(
        recentRowsStream: { recentsStream.eraseToAnyAsyncSequence() },
        localContactSearch: localSearch,
        remoteContactSearch: remoteSearch,
        ownAccountId: Data.randomOrError(of: 32),
        logger: MockLogger()
    )

    var sourcesChangedIterator = provider.sourcesChanged().makeAsyncIterator()
    provider.setup()
    continuation.yield([recentRow])
    _ = try await sourcesChangedIterator.next()

    return QueryContext(provider: provider, localSearch: localSearch, remoteSearch: remoteSearch)
}

private func collectPhases(
    from provider: AccountSearchProvider<Int>,
    query: String?
) async throws -> [AccountSearchSections<Int, ContactSearchPayload>] {
    var phases: [AccountSearchSections<Int, ContactSearchPayload>] = []

    for try await phase in provider.searchPhases(query: query) {
        phases.append(phase)
    }

    return phases
}

// MARK: - Helpers

private func makeContact(
    accountId: AccountId = Data(),
    username: String = "test_user",
    isBlocked: Bool = false
) -> Chat.Contact {
    Chat.Contact(
        accountId: accountId,
        username: username,
        publicKey: Data(repeating: 0, count: 32),
        pin: nil,
        pushId: nil,
        pushToken: nil,
        voipPushToken: nil,
        peerPlatform: nil,
        lastOwnToken: nil,
        voipLastOwnToken: nil,
        chatRequest: nil,
        ownKeyId: Chat.Contact.Own(signKeyId: "", encryptionKeyId: ""),
        imageData: nil,
        source: .chat,
        isBlocked: isBlocked,
        devices: [],
        pendingDevicesFanOut: false,
        addedAt: nil,
        acceptedAt: nil
    )
}

private func makeRemoteContact(
    accountId: AccountId = Data(),
    username: String = "test_remote"
) throws -> Chat.RemoteContact {
    try Chat.RemoteContact(
        accountId: accountId,
        username: username,
        chatPublicKey: Chat.PublicKey(rawData: Data(repeating: 0, count: 32)),
        imageData: nil,
        source: .chat
    )
}
