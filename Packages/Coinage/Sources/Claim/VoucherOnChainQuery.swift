import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import Individuality

// MARK: - Result type

struct VoucherOnChainInfo {
    let exponent: Int16
    let ringPosition: MembersPallet.RingPosition
    let isUnloaded: Bool
}

// MARK: - Protocol

/// Batch-fetches on-chain voucher state for given derivation indices.
protocol VoucherOnChainQuerying: Sendable {
    /// Fetches on-chain voucher info for multiple derivation indices in a single RPC call.
    /// Returns an array of optionals in the same order as the input indices.
    /// Returns nil for an index when either the recycler location or member record is absent.
    func fetchVouchers(
        for derivationIndices: [UInt32],
        atBlockHash: Data?
    ) async throws -> [VoucherOnChainInfo?]
}

extension VoucherOnChainQuerying {
    func fetchVouchers(
        for derivationIndices: [UInt32]
    ) async throws -> [VoucherOnChainInfo?] {
        try await fetchVouchers(for: derivationIndices, atBlockHash: nil)
    }
}

// MARK: - Implementation

/// Default implementation that queries the Recyclers and Members pallet storage via RPC.
final class VoucherOnChainQueryService: VoucherOnChainQuerying, @unchecked Sendable {
    private let connection: any JSONRPCEngine
    private let runtimeService: any RuntimeCodingServiceProtocol
    private let storageRequestFactory: any StorageRequestFactoryProtocol
    private let publicKeyProvider: (UInt32) throws -> Data
    private let aliasProvider: (UInt32) throws -> Data

    init(
        connection: any JSONRPCEngine,
        runtimeService: any RuntimeCodingServiceProtocol,
        storageRequestFactory: any StorageRequestFactoryProtocol,
        publicKeyProvider: @escaping (UInt32) throws -> Data,
        aliasProvider: @escaping (UInt32) throws -> Data
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.storageRequestFactory = storageRequestFactory
        self.publicKeyProvider = publicKeyProvider
        self.aliasProvider = aliasProvider
    }

    func fetchVouchers(
        for derivationIndices: [UInt32],
        atBlockHash: Data?
    ) async throws -> [VoucherOnChainInfo?] {
        typealias IndexedKey = (index: UInt32, publicKey: Data)
        typealias IndexedKeyWithExponent = (index: UInt32, publicKey: Data, exponent: Int16)
        typealias IndexedKeyWithPosition = (
            index: UInt32,
            exponent: Int16,
            ringIndex: MembersPallet.RingIndex,
            ringPosition: MembersPallet.RingPosition
        )

        guard !derivationIndices.isEmpty else { return [] }

        // Step 1: derive public keys — carry (index, publicKey) forward
        let indexedKeys: [IndexedKey] = try derivationIndices.map {
            try (index: $0, publicKey: publicKeyProvider($0))
        }

        // Step 2: fetch exponents — drop indices without one, carry (index, publicKey, exponent) forward
        let exponents = try await fetchExponents(
            for: indexedKeys.map(\.publicKey),
            atBlockHash: atBlockHash
        )
        let withExponents: [IndexedKeyWithExponent] =
            zip(indexedKeys, exponents).compactMap { key, exponent in
                guard let exponent else { return nil }
                return (key.index, key.publicKey, exponent)
            }

        // Step 3: fetch positions — drop indices without position or ringIndex, carry both forward
        let positions = try await fetchPositions(
            for: withExponents.map { (exponent: $0.exponent, publicKey: $0.publicKey) },
            atBlockHash: atBlockHash
        )
        let withPositions: [IndexedKeyWithPosition] =
            zip(withExponents, positions).compactMap { key, position in
                guard let position, let ringIndex = position.ringIndex else { return nil }
                return (key.index, key.exponent, ringIndex, position)
            }

        // Step 4: fetch unloaded — include unloaded with flag set so callers can track their indices
        let unloadedFlags = try await fetchUnloaded(for: withPositions.map {
            (derivationIndex: $0.index, exponent: $0.exponent, ringIndex: $0.ringIndex)
        })
        let infoByIndex: [UInt32: VoucherOnChainInfo] = zip(withPositions, unloadedFlags)
            .reduce(into: [:]) { dict, pair in
                let (key, isUnloaded) = pair
                dict[key.index] = VoucherOnChainInfo(
                    exponent: key.exponent,
                    ringPosition: key.ringPosition,
                    isUnloaded: isUnloaded
                )
            }

        return derivationIndices.map { infoByIndex[$0] }
    }
}

// MARK: - NMap key

private struct RecyclersUnloadedKey: NMapKeyStorageKeyProtocol {
    let exponent: Int16
    let ringIndex: MembersPallet.RingIndex
    let publicKey: Data

    func appendSubkey(to encoder: any DynamicScaleEncoding, type: String, index: Int) throws {
        switch index {
        case 0:
            try encoder.append(StringCodable(wrappedValue: exponent), ofType: type)
        case 1:
            try encoder.append(StringCodable(wrappedValue: ringIndex), ofType: type)
        case 2:
            try encoder.append(BytesCodable(wrappedValue: publicKey), ofType: type)
        default:
            break
        }
    }
}

// MARK: - Private queries

private extension VoucherOnChainQueryService {
    func fetchExponents(
        for publicKeys: [Data],
        atBlockHash: BlockHashData?
    ) async throws -> [Int16?] {
        let coderFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        let responses: [StringCodable<Int16>?] = try await storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { publicKeys.map { BytesCodable(wrappedValue: $0) } },
            factory: { coderFactory },
            storagePath: CoinagePallet.Storage.recyclersCoinToRecycler(),
            at: atBlockHash
        )
        .asyncExecute()
        .map(\.value)

        return responses.map { $0?.wrappedValue }
    }

    func fetchUnloaded(
        for keys: [(derivationIndex: UInt32, exponent: Int16, ringIndex: MembersPallet.RingIndex)]
    ) async throws -> [Bool] {
        guard !keys.isEmpty else { return [] }

        let coderFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        let nMapKeys: [RecyclersUnloadedKey] = try keys.map {
            let alias = try aliasProvider($0.derivationIndex)
            return RecyclersUnloadedKey(exponent: $0.exponent, ringIndex: $0.ringIndex, publicKey: alias)
        }

        let responses: [StorageResponse<JSON?>] = try await storageRequestFactory.queryNMapItems(
            engine: connection,
            nParamKeys: { nMapKeys },
            factory: { coderFactory },
            storagePath: CoinagePallet.Storage.recyclersUnloaded()
        )
        .asyncExecute()

        // For unloaded vouchers storage return empty data, not nil, but 0
        return responses
            .map(\.value)
            .map { $0 != nil }
    }

    func fetchPositions(
        for keys: [(exponent: Int16, publicKey: Data)],
        atBlockHash: BlockHashData?
    ) async throws -> [MembersPallet.RingPosition?] {
        let coderFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        return try await storageRequestFactory.queryItems(
            engine: connection,
            keyParams1: {
                keys.map { RecyclerCollectionIdentifier.identifier(for: $0.exponent) }
            },
            keyParams2: {
                keys.map { BytesCodable(wrappedValue: $0.publicKey) }
            },
            factory: { coderFactory },
            storagePath: MembersPallet.Storage.members(),
            at: atBlockHash
        )
        .asyncExecute()
        .map(\.value)
    }
}
