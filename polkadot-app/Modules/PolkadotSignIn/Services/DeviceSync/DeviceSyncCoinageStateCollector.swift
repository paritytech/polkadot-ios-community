import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt

protocol DeviceSyncCoinageStateCollecting {
    /// Handed-off coins and settled claims: everything on a full collection (`cutoff == nil`), otherwise what
    /// changed after `cutoff`. Collected after the messages, which the claim statuses refer to.
    func collect(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity]
}

struct DeviceSyncCoinageStateCollector {
    private let databaseService: CoreDataServiceProtocol

    init(databaseService: CoreDataServiceProtocol) {
        self.databaseService = databaseService
    }
}

extension DeviceSyncCoinageStateCollector: DeviceSyncCoinageStateCollecting {
    func collect(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity] {
        try await databaseService.performRead { context in
            let coins = try Self.collectHandedOffCoins(after: cutoff, in: context)
            let claims = try Self.collectSettledClaims(after: cutoff, in: context)

            return [
                coins.isEmpty ? nil : .coinsHandedOff(coins),
                claims.isEmpty ? nil : .coinageMessagesStatusUpdated(claims)
            ].compactMap { $0 }
        }
    }
}

private extension DeviceSyncCoinageStateCollector {
    /// Only committed hand-offs: a pending mark is released at launch when its message never went out.
    static func collectHandedOffCoins(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> [Chat.DeviceSyncHandedOffCoin] {
        let committed = NSPredicate(
            format: "%K == %d",
            #keyPath(CDCoin.handoffMark),
            Int(CoinHandoffMark.committed.rawValue)
        )
        let request = NSFetchRequest<CDCoin>(entityName: "CDCoin")
        request.predicate = cutoff.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                committed,
                NSPredicate(format: "%K > %@", #keyPath(CDCoin.handoffCommittedAt), $0 as NSDate)
            ])
        } ?? committed

        let mapper = CoinMapper()

        return try context.fetch(request).map { entity in
            let coin = try mapper.transform(entity: entity)
            return Chat.DeviceSyncHandedOffCoin(
                installationId: coin.derivationIndex.installation.value,
                derivationIndex: coin.derivationIndex.item,
                exponent: coin.exponent,
                age: coin.age
            )
        }
    }

    static func collectSettledClaims(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> [Chat.DeviceSyncCoinageMessageStatusUpdate] {
        let settled = NSPredicate(
            format: "%K >= %d",
            #keyPath(CDIncomingTransferState.status),
            Int(TransferStateStatus.firstTerminalRawValue)
        )
        let request = NSFetchRequest<CDIncomingTransferState>(entityName: "CDIncomingTransferState")
        request.predicate = cutoff.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                settled,
                NSPredicate(format: "%K > %@", #keyPath(CDIncomingTransferState.modifiedAt), $0 as NSDate)
            ])
        } ?? settled

        return try context.fetch(request).compactMap { row in
            guard
                let message = row.message,
                let messageId = message.messageId,
                let peer = try? message.chat?.contact?.identifier?.fromHex()
            else {
                return nil
            }

            let state = try TransferStateRows.incoming(from: row)

            return Chat.DeviceSyncCoinageMessageStatusUpdate(
                chatId: .contact(accountId: peer),
                messageId: messageId,
                status: state.status == .claimed ? .claimed : .failed,
                claimedValue: state.status == .claimed ? state.actualValue : nil
            )
        }
    }
}
