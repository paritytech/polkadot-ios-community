import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

protocol DeviceSyncCoinageStateApplying {
    func applyHandedOffCoins(_ coins: [Chat.DeviceSyncHandedOffCoin]) async throws
    /// Returns the claims whose message isn't stored yet; a caller that keeps them applies them again later.
    @discardableResult
    func applyClaimStatuses(
        _ updates: [Chat.DeviceSyncCoinageMessageStatusUpdate]
    ) async throws -> [Chat.DeviceSyncCoinageMessageStatusUpdate]
}

/// Writes coinage state received from a sibling. A handed-off coin is rebuilt from its derivation and stored as
/// committed, so it is never spent here, and a later recovery scan keeps that mark for the row it already has.
/// Nothing here marks coins or claims modified, which would send them back to their sender.
final class DeviceSyncCoinageStateApplier {
    private let databaseService: CoreDataServiceProtocol
    private let coinKeyDeriver: CoinKeyDeriving
    private let transferStateStore: TransferStateStoring
    private let logger: LoggerProtocol

    init(
        databaseService: CoreDataServiceProtocol,
        coinKeyDeriver: CoinKeyDeriving,
        transferStateStore: TransferStateStoring,
        logger: LoggerProtocol
    ) {
        self.databaseService = databaseService
        self.coinKeyDeriver = coinKeyDeriver
        self.transferStateStore = transferStateStore
        self.logger = logger
    }
}

extension DeviceSyncCoinageStateApplier: DeviceSyncCoinageStateApplying {
    func applyHandedOffCoins(_ coins: [Chat.DeviceSyncHandedOffCoin]) async throws {
        let rebuilt = try coins.map { try rebuild($0) }

        try await databaseService.performWrite { context in
            let mapper = CoinMapper()

            for coin in rebuilt {
                if let existing: CDCoin = try context.first(
                    for: NSPredicate(format: "%K == %@", #keyPath(CDCoin.identifier), coin.identifier)
                ) {
                    if existing.handoffMark == CoinHandoffMark.none.rawValue {
                        existing.handoffMark = CoinHandoffMark.committed.rawValue
                    }
                } else {
                    try mapper.populate(entity: context.insertNew(CDCoin.self), from: coin, using: context)
                }
            }
        }
    }

    @discardableResult
    func applyClaimStatuses(
        _ updates: [Chat.DeviceSyncCoinageMessageStatusUpdate]
    ) async throws -> [Chat.DeviceSyncCoinageMessageStatusUpdate] {
        var waiting: [Chat.DeviceSyncCoinageMessageStatusUpdate] = []

        for update in updates {
            guard let state = update.localState else { continue }

            do {
                try await transferStateStore.applySyncedIncoming(messageId: update.messageId, state: state)
            } catch TransferStateStoreError.messageNotFound {
                waiting.append(update)
            }
        }

        if !waiting.isEmpty {
            logger.warning("\(waiting.count) synced claim status(es) arrived before their message")
        }

        return waiting
    }
}

private extension DeviceSyncCoinageStateApplier {
    /// Saved as never seen on chain: chain sync fills in age and presence while the coin is there, and a coin
    /// the recipient already claimed is never spendable here anyway.
    func rebuild(_ coin: Chat.DeviceSyncHandedOffCoin) throws -> Coin {
        let index = try CoinageKeyIndex(
            installation: CoinageInstallationId(value: coin.installationId),
            item: coin.derivationIndex
        )

        return try Coin(
            exponent: coin.exponent,
            derivationIndex: index,
            age: nil,
            isOnchain: false,
            handoffMark: .committed,
            publicKey: coinKeyDeriver.derivePublicKey(index: index)
        )
    }
}

private extension Chat.DeviceSyncCoinageMessageStatusUpdate {
    var localState: IncomingTransferState? {
        switch status {
        case .none: nil
        case .claimed: IncomingTransferState(status: .claimed, actualValue: claimedValue)
        case .failed: IncomingTransferState(status: .failed)
        }
    }
}
