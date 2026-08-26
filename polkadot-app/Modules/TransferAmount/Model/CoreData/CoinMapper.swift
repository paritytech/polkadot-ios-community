import Foundation
import CoreData
import Coinage
import Operation_iOS

final class CoinMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Coin
    typealias CoreDataEntity = CDCoin
}

extension CoinMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        let age = entity.age >= 0 ? entity.age : nil

        return Coin(
            exponent: entity.exponent,
            derivationIndex: UInt32(bitPattern: entity.derivationIndex),
            age: age,
            state: Self.deriveState(entity: entity, age: age),
            isOnchain: entity.isOnchain
        )
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.derivationIndex = Int32(bitPattern: model.derivationIndex)
        entity.exponent = model.exponent
        entity.age = model.age ?? -1
        entity.isOnchain = model.isOnchain
        // `state` is not stored — it is derived in `transform` from the durability graph.
    }
}

// MARK: - Derivation

private extension CoinMapper {
    /// Derives the coin's local status from its durability entries, handoff mark and on-chain
    /// presence. Mirrors the balance/selection semantics the old projection materialized, now
    /// computed on read.
    static func deriveState(entity: CDCoin, age: Int16?) -> Coin.State {
        if entity.handoffMark != nil { return .handedOff }

        let consumerStatuses = ((entity.durabilityInputs as? Set<CDDurabilityInput>) ?? [])
            .compactMap { $0.entry.flatMap { EntryStatus(rawValue: Int($0.status)) } }
        let minterStatus = entity.durabilityOutput?.entry.flatMap { EntryStatus(rawValue: Int($0.status)) }

        // Spent: consumed by a finalized entry, minted by a failed one, or seen on chain and gone.
        if consumerStatuses.contains(.finalizedSuccess) { return .spent }
        if minterStatus == .failure { return .spent }
        if age != nil, !entity.isOnchain { return .spent }

        // Reserved by any live entry — a transfer or a recycling.
        if consumerStatuses.contains(where: { $0 == .pending || $0 == .pendingSuccess }) {
            return .pendingTransfer
        }

        // Output of a still-pending entry.
        if minterStatus == .pending { return .pendingMint }

        return .available
    }
}
