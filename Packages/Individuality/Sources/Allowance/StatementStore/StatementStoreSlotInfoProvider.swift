import Foundation
import SubstrateSdk
import Operation_iOS
import SubstrateStorageQuery
import KeyDerivation
import FoundationExt
import ChainStore
import SDKLogger

public struct SSSSlotInfo {
    public let period: UInt32
    public let seq: UInt32
    public let personOrigin: PersonOrigin

    public init(
        period: UInt32,
        seq: UInt32,
        personOrigin: PersonOrigin
    ) {
        self.period = period
        self.seq = seq
        self.personOrigin = personOrigin
    }
}

public protocol StatementStoreSlotInfoProviding {
    func hasExistingSlot(for accountId: AccountId) async throws -> Bool
    func freeSlot(excluding accountId: AccountId) async throws -> SSSSlotInfo
}

public final class StatementStoreSlotInfoProvider: StatementStoreSlotInfoProviding {
    private let chainId: ChainId
    private let chainRegistry: ChainResourceProtocol
    private let storageRequestFactory: StorageRequestFactoryProtocol
    private let keyResolver: BandersnatchKeyResolving
    private let logger: SDKLoggerProtocol

    public init(
        chainId: ChainId,
        chainRegistry: ChainResourceProtocol,
        storageRequestFactory: StorageRequestFactoryProtocol,
        keyResolver: BandersnatchKeyResolving,
        logger: SDKLoggerProtocol
    ) {
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.storageRequestFactory = storageRequestFactory
        self.keyResolver = keyResolver
        self.logger = logger
    }

    public func hasExistingSlot(for accountId: AccountId) async throws -> Bool {
        let state = try await fetchState()
        return state.entries.contains { $0.value?.accountId == accountId }
    }

    public func freeSlot(excluding accountId: AccountId) async throws -> SSSSlotInfo {
        let state = try await fetchState()

        if let freeIndex = state.entries.firstIndex(where: { $0.value == nil }) {
            logger.debug("Found free index: \(freeIndex)")

            return SSSSlotInfo(
                period: state.period,
                seq: UInt32(freeIndex),
                personOrigin: state.personOrigin
            )
        }

        let cooldown = try await fetchReplacementCooldown(codingFactory: state.codingFactory)
        let nowSeconds = UInt64(Date().timeIntervalSince1970)

        let oldest = state.entries.enumerated()
            .compactMap { index, response -> (index: Int, entry: ResourcesPallet.StmtStoreAllowanceEntry)? in
                guard let entry = response.value else { return nil }
                guard entry.accountId != accountId else { return nil }
                guard nowSeconds >= entry.since + UInt64(cooldown) else { return nil }
                return (index, entry)
            }
            .min(by: { $0.entry.since < $1.entry.since })

        guard let oldest else {
            let minSince = state.entries.compactMap(\.value)
                .filter { $0.accountId != accountId }
                .min(by: { $0.since < $1.since })?.since ?? nowSeconds

            let secsToWait = TimeInterval(minSince + UInt64(cooldown)) - TimeInterval(nowSeconds)

            throw StatementStoreAllowanceError.noSlotsAvailable(
                secsToWait: max(secsToWait, 0)
            )
        }

        logger.debug("Found slot to evict: \(oldest.index)")

        return SSSSlotInfo(
            period: state.period,
            seq: UInt32(oldest.index),
            personOrigin: state.personOrigin
        )
    }
}

private extension StatementStoreSlotInfoProvider {
    struct SlotState {
        let entries: [StorageResponse<ResourcesPallet.StmtStoreAllowanceEntry>]
        let personOrigin: PersonOrigin
        let period: UInt32
        let codingFactory: RuntimeCoderFactoryProtocol
    }

    func fetchState() async throws -> SlotState {
        // TODO: system time should be replaced with on-chain timestamp
        let period = UInt32(Date().timeIntervalSince1970 / TimeInterval.secondsInDay)

        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chainId)
        let connection = try chainRegistry.getRpcConnectionOrError(for: chainId)

        let personOrigin = try await OriginPersonProvider(
            liteVrfManager: keyResolver.liteKeyManager,
            liteCollectionId: PeopleLitePallet.membersIdentifier,
            fullVrfManager: keyResolver.fullKeyManager,
            fullCollectionId: PeoplePallet.membersIdentifier,
            memberStatusChecker: MembershipStatusChecker(
                connection: connection,
                runtimeCodingService: runtimeProvider
            )
        ).pickPersonOrigin()

        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        let maxSlots = try await fetchMaxSlots(origin: personOrigin, codingFactory: codingFactory)
        guard maxSlots > 0 else { throw AllowanceSlotAssignmentError.noSlotsAvailable }

        let activeVrfManager = personOrigin.keyManager
        let aliases = try (0 ..< maxSlots).map { seq in
            let context = SSSSlotContextBuilder.context(period: period, seq: seq)
            return try activeVrfManager.deriveAlias(for: context)
        }

        let periodBytes = Data(period.bigEndianBytes)
        let entries: [StorageResponse<ResourcesPallet.StmtStoreAllowanceEntry>] =
            try await storageRequestFactory.queryItems(
                engine: connection,
                keyParams1: { Array(repeating: BytesCodable(wrappedValue: periodBytes), count: aliases.count) },
                keyParams2: { aliases.map { BytesCodable(wrappedValue: $0) } },
                factory: { codingFactory },
                storagePath: ResourcesPallet.statementStoreAllowances
            )
            .asyncExecute()

        return SlotState(
            entries: entries,
            personOrigin: personOrigin,
            period: period,
            codingFactory: codingFactory
        )
    }

    func fetchMaxSlots(
        origin: PersonOrigin,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> UInt32 {
        let path =
            switch origin {
            case .lite: ResourcesPallet.Constants.liteStmtStoreSlotsPerPeriod()
            case .full: ResourcesPallet.Constants.stmtStoreSlotsPerPeriod()
            }
        let operation = StorageConstantOperation<StringCodable<UInt32>>(
            path: path,
            fallbackValue: .init(wrappedValue: 0)
        )
        operation.codingFactory = codingFactory
        return try await operation.asyncExecute().wrappedValue
    }

    func fetchReplacementCooldown(
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> UInt32 {
        let operation = StorageConstantOperation<StringCodable<UInt32>>(
            path: ResourcesPallet.Constants.stmtStoreReplacementCooldown(),
            fallbackValue: .init(wrappedValue: 0)
        )
        operation.codingFactory = codingFactory
        return try await operation.asyncExecute().wrappedValue
    }
}
