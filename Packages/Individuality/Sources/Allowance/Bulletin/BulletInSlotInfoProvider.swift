import Foundation
import ChainStore
import KeyDerivation
import SubstrateStorageQuery
import SubstrateStorageSubscription
import Operation_iOS
import BulletinChain
import SubstrateSdk
import SubstrateSdkExt
import SubstrateOperation
import StructuredConcurrency
import AsyncExtensions

public struct BulletInFreeSlotInfo {
    public let counter: UInt8
    public let period: UInt32
    public let personOrigin: PersonOrigin
}

public struct BulletInAllowanceInfo {
    public let remainedSize: UInt64
    public let remainedTransactions: UInt32
    public let expiresIn: BlockNumber
    public let fetchedAt: BlockNumber

    public var isExpired: Bool {
        fetchedAt >= expiresIn
    }

    public var available: Bool {
        remainedSize > 0 && remainedTransactions > 0 && !isExpired
    }

    public init(
        remainedSize: UInt64,
        remainedTransactions: UInt32,
        expiresIn: BlockNumber,
        fetchedAt: BlockNumber
    ) {
        self.remainedSize = remainedSize
        self.remainedTransactions = remainedTransactions
        self.expiresIn = expiresIn
        self.fetchedAt = fetchedAt
    }
}

public protocol BulletInSlotInfoProviding {
    func fetchFreeSlotInfo() async throws -> BulletInFreeSlotInfo
    func fetchAllowance(for accountId: AccountId) async throws -> BulletInAllowanceInfo?
    func waitAuthorization(
        for accountId: AccountId,
        currentAllowance: BulletInAllowanceInfo?,
        timeout: Duration
    ) async throws
}

enum BulletInSlotInfoProviderError: Error {
    case noAuthorization
    case authorizationWaitTimeout
}

public final class BulletInSlotInfoProvider {
    let bulletInChainId: ChainId
    let peopleChainId: ChainId
    let chainRegistry: ChainResourceProtocol
    let keyResolver: BandersnatchKeyResolving
    let bulletInBlockProvider: BlockInfoProviding
    let operationQueue: OperationQueue

    let storageRequestFactory: StorageRequestFactoryProtocol

    public init(
        bulletInChainId: ChainId,
        peopleChainId: ChainId,
        chainRegistry: ChainResourceProtocol,
        keyResolver: BandersnatchKeyResolving,
        operationQueue: OperationQueue
    ) {
        self.bulletInChainId = bulletInChainId
        self.peopleChainId = peopleChainId
        self.chainRegistry = chainRegistry
        self.keyResolver = keyResolver
        self.operationQueue = operationQueue
        bulletInBlockProvider = BlockInfoProvider(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            chainId: bulletInChainId
        )

        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}

extension BulletInSlotInfoProvider: BulletInSlotInfoProviding {
    public func fetchFreeSlotInfo() async throws -> BulletInFreeSlotInfo {
        let peopleConnection = try chainRegistry.getRpcConnectionOrError(for: peopleChainId)
        let peopleRuntimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: peopleChainId)
        let codingFactory = try await peopleRuntimeProvider.fetchCoderFactoryOperation().asyncExecute()
        let periodDuration = try await fetchPeriodDuration(codingFactory: codingFactory)

        let personOrigin = try await OriginPersonProvider(
            liteVrfManager: keyResolver.liteKeyManager,
            liteCollectionId: PeopleLitePallet.membersIdentifier,
            fullVrfManager: keyResolver.fullKeyManager,
            fullCollectionId: PeoplePallet.membersIdentifier,
            memberStatusChecker: MembershipStatusChecker(
                connection: peopleConnection,
                runtimeCodingService: peopleRuntimeProvider
            )
        ).pickPersonOrigin()

        let maxClaims = try await fetchMaxClaims(codingFactory: codingFactory)

        guard maxClaims > 0, periodDuration > 0 else {
            throw AllowanceSlotAssignmentError.noSlotsAvailable
        }

        let period = UInt32(Date().timeIntervalSince1970 / TimeInterval(periodDuration))

        let aliases = try (0 ..< maxClaims).map { counter -> Data in
            let context = BulletinSlotContextBuilder.context(period: period, counter: counter)
            return try personOrigin.keyManager.deriveAlias(for: context)
        }

        let periodBytes = Data(period.bigEndianBytes)

        let responses: [StorageResponse<JSON>] =
            try await storageRequestFactory.queryItems(
                engine: peopleConnection,
                keyParams1: { aliases.map { _ in BytesCodable(wrappedValue: periodBytes) } },
                keyParams2: { aliases.map { BytesCodable(wrappedValue: $0) } },
                factory: { codingFactory },
                storagePath: ResourcesPallet.spentLongTermStorageAliases
            )
            .asyncExecute()

        guard let index = responses.firstIndex(where: { $0.data == nil }) else {
            throw AllowanceSlotAssignmentError.noSlotsAvailable
        }

        return BulletInFreeSlotInfo(
            counter: UInt8(index),
            period: period,
            personOrigin: personOrigin
        )
    }

    public func fetchAllowance(for accountId: AccountId) async throws -> BulletInAllowanceInfo? {
        let connection = try chainRegistry.getRpcConnectionOrError(for: bulletInChainId)
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: bulletInChainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        let authorizations: TransactionStoragePallet.Authorization? = try await storageRequestFactory.queryItems(
            engine: connection,
            keyParams: {
                [TransactionStoragePallet.AuthorizationScope.account(accountId)]
            },
            factory: { codingFactory },
            storagePath: TransactionStoragePallet.authorizationsPath
        )
        .asyncExecute()
        .first?.value

        guard let authorizations else {
            return nil
        }

        let blockNumber: BlockNumber = try await bulletInBlockProvider.fetchCurrent()

        return BulletInAllowanceInfo(
            remainedSize: authorizations.extent.remainedBytes,
            remainedTransactions: authorizations.extent.remainedTransactions,
            expiresIn: authorizations.expiration,
            fetchedAt: blockNumber
        )
    }

    public func waitAuthorization(
        for accountId: AccountId,
        currentAllowance: BulletInAllowanceInfo?,
        timeout: Duration
    ) async throws {
        let connection = try chainRegistry.getRpcConnectionOrError(for: bulletInChainId)
        let runtimeService = try chainRegistry.getRuntimeCodingServiceOrError(for: bulletInChainId)

        let request = MapSubscriptionRequest(
            storagePath: TransactionStoragePallet.authorizationsPath,
            localKey: "",
            keyParamClosure: {
                TransactionStoragePallet.AuthorizationScope.account(accountId)
            }
        )

        let batchRequest = BatchStorageSubscriptionRequest(
            innerRequest: request,
            mappingKey: nil
        )

        let stream: AnyAsyncSequence<BatchStorageSubscriptionSingleResult<TransactionStoragePallet.Authorization?>>
        stream = CallbackBatchStorageSubscription.asyncStream(
            requests: [batchRequest],
            connection: connection,
            runtimeService: runtimeService,
            logger: nil
        )

        do {
            let currentRemainedTransactions = currentAllowance?.remainedTransactions ?? 0
            try await withTimeout(timeout) {
                for try await result in stream {
                    if
                        let authorization = result.value,
                        authorization.extent.remainedTransactions > currentRemainedTransactions {
                        return
                    }
                }
            }
        } catch is TimeoutError {
            throw BulletInSlotInfoProviderError.authorizationWaitTimeout
        }
    }
}

private extension BulletInSlotInfoProvider {
    func fetchMaxClaims(codingFactory: RuntimeCoderFactoryProtocol) async throws -> UInt8 {
        let operation = StorageConstantOperation<StringCodable<UInt8>>(
            path: ResourcesPallet.Constants.longTermStorageClaimsPerPeriod(),
            fallbackValue: .init(wrappedValue: 0)
        )
        operation.codingFactory = codingFactory
        return try await operation.asyncExecute().wrappedValue
    }

    func fetchPeriodDuration(codingFactory: RuntimeCoderFactoryProtocol) async throws -> UInt32 {
        let operation = StorageConstantOperation<StringCodable<UInt32>>(
            path: ResourcesPallet.Constants.longTermStoragePeriodDuration(),
            fallbackValue: nil
        )
        operation.codingFactory = codingFactory
        return try await operation.asyncExecute().wrappedValue
    }
}
