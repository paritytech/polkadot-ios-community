import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt

protocol DeviceSyncCoinageStateCollecting {
    /// Handed-off coins, settled claims and settled outgoing transfers: everything on a full collection
    /// (`cutoff == nil`), otherwise what changed after `cutoff`. Collected after the messages the statuses refer to.
    func collect(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity]
    /// Rows `collect` reads; a row it can't map isn't sent, so this can be slightly higher.
    func count(after cutoff: Date?) async throws -> Int
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
            let outgoing = try Self.collectSettledOutgoing(after: cutoff, in: context)

            return [
                coins.isEmpty ? nil : .coinsHandedOff(coins),
                claims.isEmpty ? nil : .coinageMessagesStatusUpdated(claims),
                outgoing.isEmpty ? nil : .outgoingTransferStatesUpdated(outgoing)
            ].compactMap { $0 }
        }
    }

    func count(after cutoff: Date?) async throws -> Int {
        try await databaseService.performRead { context in
            try context.count(for: Self.handedOffCoinsRequest(after: cutoff))
                + context.count(for: Self.settledClaimsRequest(after: cutoff))
                + context.count(for: Self.settledOutgoingRequest(after: cutoff))
        }
    }
}

private extension DeviceSyncCoinageStateCollector {
    static func collectHandedOffCoins(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> [Chat.DeviceSyncHandedOffCoin] {
        let mapper = CoinMapper()

        return try context.fetch(handedOffCoinsRequest(after: cutoff)).map { entity in
            let coin = try mapper.transform(entity: entity)
            return Chat.DeviceSyncHandedOffCoin(
                installationId: coin.derivationIndex.installation.value,
                derivationIndex: coin.derivationIndex.item,
                exponent: coin.exponent
            )
        }
    }

    static func collectSettledClaims(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> [Chat.DeviceSyncCoinageMessageStatusUpdate] {
        try context.fetch(settledClaimsRequest(after: cutoff)).compactMap { row in
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
                status: state.status == .claimed ? .claimed(partial: state.actualValue) : .failed
            )
        }
    }

    static func collectSettledOutgoing(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> [Chat.DeviceSyncCoinageMessageStatusUpdate] {
        try context.fetch(settledOutgoingRequest(after: cutoff)).compactMap { row in
            guard
                let message = row.message,
                let messageId = message.messageId,
                let peer = try? message.chat?.contact?.identifier?.fromHex()
            else {
                return nil
            }

            let state = try TransferStateRows.outgoing(from: row)

            return Chat.DeviceSyncCoinageMessageStatusUpdate(
                chatId: .contact(accountId: peer),
                messageId: messageId,
                status: state.status == .claimed ? .claimed(partial: state.actualValue) : .failed
            )
        }
    }
}

private extension DeviceSyncCoinageStateCollector {
    /// Only committed hand-offs: a pending mark is released at launch when its message never went out.
    static func handedOffCoinsRequest(after cutoff: Date?) -> NSFetchRequest<CDCoin> {
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
        return request
    }

    static func settledOutgoingRequest(after cutoff: Date?) -> NSFetchRequest<CDOutgoingTransferState> {
        let settled = NSPredicate(
            format: "%K >= %d",
            #keyPath(CDOutgoingTransferState.status),
            Int(TransferStateStatus.firstTerminalRawValue)
        )
        let request = NSFetchRequest<CDOutgoingTransferState>(entityName: "CDOutgoingTransferState")
        request.predicate = cutoff.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                settled,
                NSPredicate(format: "%K > %@", #keyPath(CDOutgoingTransferState.modifiedAt), $0 as NSDate)
            ])
        } ?? settled
        return request
    }

    static func settledClaimsRequest(after cutoff: Date?) -> NSFetchRequest<CDIncomingTransferState> {
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
        return request
    }
}
