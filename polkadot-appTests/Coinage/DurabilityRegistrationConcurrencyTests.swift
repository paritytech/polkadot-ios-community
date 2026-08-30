import Coinage
import CoreData
import Foundation
import Testing

@testable import polkadot_app

/// Guards the serialization of `CoinageTransactionContext.withTransaction`.
///
/// It once built a new `NSManagedObjectContext` per call instead of using the shared serial one,
/// so two concurrent registrations each read the store before either saved, neither saw the other,
/// both passed the Unique consumer invariant, and both committed — double-spending an input and
/// assigning duplicate `sequence` values.
///
/// Also pins the other half of Unique consumer: a `failure` entry must not keep holding its
/// inputs, or retry after failure would be impossible.
@Suite("Durability registration concurrency")
final class DurabilityRegistrationConcurrencyTests {
    private var facade: UserDataStorageTestFacade!
    private var store: DurabilityCoreDataStore!

    init() {
        facade = UserDataStorageTestFacade()
        let transacting = CoinageTransactionContext(databaseService: facade.databaseService)
        store = DurabilityCoreDataStore(
            storageFacade: facade,
            transacting: transacting,
            coinKeyDeriver: StubCoinKeyDeriver()
        )
    }

    @Test("concurrent registrations on the same input admit exactly one")
    func concurrentRegistrationsOnSameInputAdmitExactlyOne() async throws {
        for _ in 0 ..< 50 {
            let facade = UserDataStorageTestFacade()
            let transacting = CoinageTransactionContext(databaseService: facade.databaseService)
            let store = DurabilityCoreDataStore(
                storageFacade: facade,
                transacting: transacting,
                coinKeyDeriver: StubCoinKeyDeriver()
            )
            try await persistCoins([0, 1, 2], facade: facade)

            let sharedInput = DurabilityInput.coin(.own(0))
            let id1 = TransactionId()
            let id2 = TransactionId()

            let entry1 = DurabilityEntry(
                id: id1,
                inputs: [sharedInput],
                outputs: [.coin(1)],
                checkpoint: BlockRef(number: 100, hash: Data([100])),
                mortality: 64,
                successDetectedAt: nil
            )

            let entry2 = DurabilityEntry(
                id: id2,
                inputs: [sharedInput],
                outputs: [.coin(2)],
                checkpoint: BlockRef(number: 100, hash: Data([100])),
                mortality: 64,
                successDetectedAt: nil
            )

            var firstError: Error?
            var secondError: Error?
            var firstSucceeded = false
            var secondSucceeded = false

            async let task1: () = Task {
                do {
                    try await store.register(entry1)
                    firstSucceeded = true
                } catch {
                    firstError = error
                }
            }.value

            async let task2: () = Task {
                do {
                    try await store.register(entry2)
                    secondSucceeded = true
                } catch {
                    secondError = error
                }
            }.value

            _ = await (task1, task2)

            // Exactly one should succeed
            let successCount = (firstSucceeded ? 1 : 0) + (secondSucceeded ? 1 : 0)
            #expect(successCount == 1)

            // The rejected one should throw inputAlreadyClaimed
            if firstSucceeded {
                #expect((secondError as? DurabilityError) == .inputAlreadyClaimed(sharedInput.identifier))
            } else {
                #expect((firstError as? DurabilityError) == .inputAlreadyClaimed(sharedInput.identifier))
            }
        }
    }

    @Test("concurrent registrations keep sequence monotonic")
    func concurrentRegistrationsKeepSequenceMonotonic() async throws {
        for _ in 0 ..< 50 {
            let facade = UserDataStorageTestFacade()
            let transacting = CoinageTransactionContext(databaseService: facade.databaseService)
            let store = DurabilityCoreDataStore(
                storageFacade: facade,
                transacting: transacting,
                coinKeyDeriver: StubCoinKeyDeriver()
            )
            try await persistCoins((0 ..< 10).map(UInt64.init) + (100 ..< 110).map(UInt64.init), facade: facade)

            let entries = (0 ..< 10).map { i in
                DurabilityEntry(
                    id: TransactionId(),
                    inputs: [.coin(.own(UInt64(i)))],
                    outputs: [.coin(UInt64(100 + i))],
                    checkpoint: BlockRef(number: 100, hash: Data([100])),
                    mortality: 64,
                    successDetectedAt: nil
                )
            }

            var registrationErrors: [Error] = []

            await withTaskGroup(of: Void.self) { group in
                for entry in entries {
                    group.addTask {
                        do {
                            try await store.register(entry)
                        } catch {
                            registrationErrors.append(error)
                        }
                    }
                }
                await group.waitForAll()
            }

            // All registrations should succeed
            #expect(registrationErrors.isEmpty)

            // Fetch all entries and check sequences
            let fetched = try await store.fetchAll()
            #expect(fetched.count == 10)

            let sequences = fetched.map(\.sequence)
            let uniqueSequences = Set(sequences)

            #expect(uniqueSequences.count == 10)

            // Sequences should be contiguous starting from 1
            let sortedSequences = sequences.sorted()
            let expectedSequences = (1 ... 10).map { Int64($0) }
            #expect(sortedSequences == expectedSequences)
        }
    }

    @Test("rejected registration leaves nothing behind")
    func rejectedRegistrationLeavesNothingBehind() async throws {
        try await persistCoins([0, 1, 2], facade: facade)

        // First registration should succeed
        let firstInput = DurabilityInput.coin(.own(0))
        let firstEntry = DurabilityEntry(
            id: TransactionId(),
            inputs: [firstInput],
            outputs: [.coin(1)],
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64,
            successDetectedAt: nil
        )

        try await store.register(firstEntry)

        // Verify we have exactly one entry
        var entries = try await store.fetchAll()
        #expect(entries.count == 1)

        // Second registration attempts to use the same input — should be rejected
        let secondEntry = DurabilityEntry(
            id: TransactionId(),
            inputs: [firstInput],
            outputs: [.coin(2)],
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64,
            successDetectedAt: nil
        )

        var rejectionError: Error?
        do {
            try await store.register(secondEntry)
        } catch {
            rejectionError = error
        }

        // Verify rejection happened
        #expect((rejectionError as? DurabilityError) == .inputAlreadyClaimed(firstInput.identifier))

        // Verify store still holds only the first entry and no marks
        entries = try await store.fetchAll()
        #expect(entries.count == 1)

        // Verify no handoff marks were left behind
        let marks = try await store.handedOffCoins()
        #expect(marks.isEmpty)
    }

    /// Unique consumer excludes `failure` entries, so an input released by a failed entry can be
    /// spent again. This pins the relationship traversal in `claimedInputIdentifiers`: if the
    /// predicate did not reach through to the owning entry's status, every retry after a failure
    /// would be rejected as a double-spend.
    @Test("an input claimed only by a failed entry can be registered again")
    func inputOfFailedEntryIsRegistrableAgain() async throws {
        try await persistCoins([7, 1, 2], facade: facade)

        let input = DurabilityInput.coin(.own(7))
        let failedId = TransactionId()

        let failedEntry = DurabilityEntry(
            id: failedId,
            inputs: [input],
            outputs: [.coin(1)],
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64
        )

        try await store.register(failedEntry)
        try await store.updateStatus(failedId, to: .failure)

        // The retry reuses the input but mints a different output — a fresh output is a separate
        // invariant and would mask the one under test.
        let retry = DurabilityEntry(
            id: TransactionId(),
            inputs: [input],
            outputs: [.coin(2)],
            checkpoint: BlockRef(number: 200, hash: Data([200])),
            mortality: 64
        )

        try await store.register(retry)

        let entries = try await store.fetchAll()
        #expect(entries.count == 2)
        #expect(entries.filter { $0.status == .failure }.count == 1)
    }

    @Test("an input claimed by a live entry is still rejected after another entry fails")
    func liveClaimSurvivesUnrelatedFailure() async throws {
        try await persistCoins([7, 8, 1, 2, 3], facade: facade)

        let liveInput = DurabilityInput.coin(.own(7))
        let failedId = TransactionId()

        let failedEntry = DurabilityEntry(
            id: failedId,
            inputs: [.coin(.own(8))],
            outputs: [.coin(1)],
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64
        )
        let liveEntry = DurabilityEntry(
            id: TransactionId(),
            inputs: [liveInput],
            outputs: [.coin(2)],
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64
        )

        try await store.register(failedEntry)
        try await store.register(liveEntry)
        try await store.updateStatus(failedId, to: .failure)

        let conflicting = DurabilityEntry(
            id: TransactionId(),
            inputs: [liveInput],
            outputs: [.coin(3)],
            checkpoint: BlockRef(number: 200, hash: Data([200])),
            mortality: 64
        )

        await #expect(throws: DurabilityError.inputAlreadyClaimed(liveInput.identifier)) {
            try await store.register(conflicting)
        }
    }

    /// Coins must exist before a transaction registers against them, so persist the input and
    /// output coins a test references before it registers any entry.
    private func persistCoins(_ indices: [DerivationIndex], facade: UserDataStorageTestFacade) async throws {
        let repo = facade.makeRepo(mapper: CoinMapper())
        let deriver = StubCoinKeyDeriver()
        let coins = try indices.map {
            try Coin(exponent: 0, derivationIndex: $0, age: nil, publicKey: deriver.derivePublicKey(index: $0))
        }
        try await repo.saveOperation({ coins }, { [] }).asyncExecute()
    }
}

/// Deterministic coin public key from the derivation index — enough for registration validation,
/// which only needs distinct, stable keys.
private struct StubCoinKeyDeriver: CoinKeyDeriving {
    func derivePublicKey(index: DerivationIndex) throws -> PublicKey {
        withUnsafeBytes(of: index.bigEndian) { Data($0) }
    }

    func derivePrivateKey(index _: DerivationIndex) throws -> PrivateKey {
        Data()
    }
}
