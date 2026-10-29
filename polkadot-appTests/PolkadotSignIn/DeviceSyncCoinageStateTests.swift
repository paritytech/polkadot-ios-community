@testable import polkadot_app
import BigInt
import Coinage
import CoreData
import Foundation
import Operation_iOS
import SubstrateSdk
import Testing

/// The old phone (`sender`) is collected and applied to the new phone (`receiver`), both real in-memory stores
/// with the same chat.
@Suite(.timeLimit(.minutes(1)))
struct DeviceSyncCoinageStateTests {
    private let sender = TransferStateTestWorld()
    private let receiver = TransferStateTestWorld()
    private let keyDeriver = CoinKeypairFactory(entropyManager: FixedRootEntropyManager())

    init() async throws {
        try await sender.setup()
        try await receiver.setup()
    }

    @Test("A coin handed off on the old phone can't be spent on the new one")
    func handedOffCoinIsNotSpendable() async throws {
        let coin = try makeCoin(item: 3, handoffMark: .committed)
        try await save(coin, in: sender.facade)

        try await transfer(after: nil)

        let handedOff = try await CoinageAssetLedgerCoreData(storageFacade: receiver.facade).getHandoffKeys()
        #expect(handedOff == [coin.publicKey])
    }

    @Test("A coin the new phone already recovered as free becomes handed off")
    func recoveredFreeCoinBecomesHandedOff() async throws {
        try await save(makeCoin(item: 4, handoffMark: .committed), in: sender.facade)
        let recovered = try makeCoin(item: 4, handoffMark: .none)
        try await save(recovered, in: receiver.facade)

        try await transfer(after: nil)

        let handedOff = try await CoinageAssetLedgerCoreData(storageFacade: receiver.facade).getHandoffKeys()
        #expect(handedOff == [recovered.publicKey])
    }

    @Test("A settled claim isn't claimed again on the new phone, and a partial one keeps its amount")
    func settledClaimsAreNotClaimedAgain() async throws {
        let partial = try await saveIncomingTransfer(totalValue: 10)
        let failed = try await saveIncomingTransfer(totalValue: 5)
        let pending = try await saveIncomingTransfer(totalValue: 7)
        try await sender.store.updateIncoming(
            messageId: partial.messageId,
            state: IncomingTransferState(status: .claimed, actualValue: 4)
        )
        try await sender.store.updateIncoming(
            messageId: failed.messageId,
            state: IncomingTransferState(status: .failed)
        )

        try await transfer(after: nil)

        #expect(try await claimableMessageIds() == [pending.messageId])
        #expect(try await receiver.transfer(partial.messageId)?.state == .incoming(
            IncomingTransferState(status: .claimed, actualValue: 4)
        ))
    }

    @Test("A claim that arrives before its message is held back and applies once the message is stored")
    func claimBeforeItsMessageIsHeldBack() async throws {
        let message = try await sender.saveTransfer(.incoming, totalValue: 6)
        try await sender.store.updateIncoming(
            messageId: message.messageId,
            state: IncomingTransferState(status: .failed)
        )
        let entities = try await DeviceSyncCoinageStateCollector(databaseService: sender.facade.databaseService)
            .collect(after: nil)
        let applier = makeApplier()
        guard case let .coinageMessagesStatusUpdated(updates)? = entities.last else {
            Issue.record("Expected claim statuses, got \(entities.map(\.logLabel))")
            return
        }

        let waiting = try await applier.applyClaimStatuses(updates)
        try await ChatMessageRepositoryFactory(storageFacade: receiver.facade)
            .createRepository(forFilter: nil)
            .saveOperation({ [message] }, { [] })
            .asyncExecute()
        let stillWaiting = try await applier.applyClaimStatuses(waiting)

        #expect(waiting.map(\.messageId) == [message.messageId])
        #expect(stillWaiting.isEmpty)
        #expect(try await claimableMessageIds().isEmpty)
    }

    @Test("Hand-offs and claims after the checkpoint travel incrementally")
    func incrementalChangesAfterCheckpoint() async throws {
        try await save(makeCoin(item: 1, handoffMark: .committed), in: sender.facade)
        let checkpoint = Date()
        let later = try makeCoin(item: 2, handoffMark: .none)
        try await save(later, in: sender.facade)
        try await commitHandoff(of: later)
        let message = try await saveIncomingTransfer(totalValue: 3)
        try await sender.store.updateIncoming(
            messageId: message.messageId,
            state: IncomingTransferState(status: .failed)
        )

        try await transfer(after: checkpoint)

        let handedOff = try await CoinageAssetLedgerCoreData(storageFacade: receiver.facade).getHandoffKeys()
        #expect(handedOff == [later.publicKey])
        #expect(try await claimableMessageIds().isEmpty)
    }

    @Test("Applying synced coinage state doesn't mark it modified, so it isn't sent back")
    func appliedStateIsNotEchoed() async throws {
        try await save(makeCoin(item: 5, handoffMark: .committed), in: sender.facade)
        let message = try await saveIncomingTransfer(totalValue: 2)
        try await sender.store.updateIncoming(
            messageId: message.messageId,
            state: IncomingTransferState(status: .failed)
        )
        let checkpoint = Date()

        try await transfer(after: nil)

        let echoed = try await DeviceSyncCoinageStateCollector(databaseService: receiver.facade.databaseService)
            .collect(after: checkpoint)
        #expect(echoed.isEmpty)
    }
}

private extension DeviceSyncCoinageStateTests {
    func transfer(after cutoff: Date?) async throws {
        let entities = try await DeviceSyncCoinageStateCollector(databaseService: sender.facade.databaseService)
            .collect(after: cutoff)
        let applier = makeApplier()

        for entity in entities {
            switch entity {
            case let .coinsHandedOff(coins): try await applier.applyHandedOffCoins(coins)
            case let .coinageMessagesStatusUpdated(updates): try await applier.applyClaimStatuses(updates)
            default: Issue.record("Unexpected entity \(entity.logLabel)")
            }
        }
    }

    func makeApplier() -> DeviceSyncCoinageStateApplier {
        DeviceSyncCoinageStateApplier(
            databaseService: receiver.facade.databaseService,
            coinKeyDeriver: keyDeriver,
            transferStateStore: receiver.store,
            logger: MockLogger()
        )
    }

    func makeCoin(item: DerivationIndex, handoffMark: CoinHandoffMark) throws -> Coin {
        let index = try CoinageKeyIndex(
            installation: CoinageInstallationId(value: Data(repeating: 0x0C, count: CoinageInstallationId.sizeBytes)),
            item: item
        )
        return try Coin(
            exponent: 2,
            derivationIndex: index,
            age: 1,
            isOnchain: true,
            handoffMark: handoffMark,
            publicKey: keyDeriver.derivePublicKey(index: index)
        )
    }

    func save(_ coin: Coin, in facade: UserDataStorageTestFacade) async throws {
        try await facade.createRepository(mapper: AnyCoreDataMapper(CoinMapper()))
            .saveOperation({ [coin] }, { [] })
            .asyncExecute()
    }

    func commitHandoff(of coin: Coin) async throws {
        let ledger = CoinageAssetLedgerCoreData(storageFacade: sender.facade)
        try await sender.facade.databaseService.performWrite { context in
            try ledger.commitHandoffs([coin.publicKey], in: CoreDataRegistrationScope(context: context))
        }
    }

    /// The same incoming transfer message on both phones, as the message sync leaves it.
    func saveIncomingTransfer(totalValue: Balance) async throws -> Chat.LocalMessage {
        let message = try await sender.saveTransfer(.incoming, totalValue: totalValue)
        try await ChatMessageRepositoryFactory(storageFacade: receiver.facade)
            .createRepository(forFilter: nil)
            .saveOperation({ [message] }, { [] })
            .asyncExecute()
        return message
    }

    func claimableMessageIds() async throws -> [Chat.MessageId] {
        try await ChatMessageRepositoryFactory(storageFacade: receiver.facade)
            .createRepository(forFilter: .incomingCoinageSendMessages())
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .map(\.messageId)
    }
}
