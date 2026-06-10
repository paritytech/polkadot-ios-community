import Foundation
import ExtrinsicService
import SubstrateSdk
import SubstrateStorageQuery
import KeyDerivation
import ChainStore

public protocol AsResourcesOriginCreating {
    func createSSSOrigin(
        personOrigin: PersonOrigin,
        period: UInt32,
        seq: UInt32,
        chain: ChainId
    ) async throws -> ExtrinsicOriginDefining

    func createLTSOrigin(
        personOrigin: PersonOrigin,
        period: UInt32,
        counter: UInt8,
        chain: ChainId
    ) async throws -> ExtrinsicOriginDefining
}

public final class AsResourcesOriginFactory: AsResourcesOriginCreating {
    private let wallet: WalletManaging
    private let keyResolver: BandersnatchKeyResolving
    private let chainRegistry: ChainResourceProtocol

    private lazy var requestFactory = StorageRequestFactory.asyncInit()

    public init(
        wallet: WalletManaging,
        keyResolver: BandersnatchKeyResolving,
        chainRegistry: ChainResourceProtocol
    ) {
        self.wallet = wallet
        self.keyResolver = keyResolver
        self.chainRegistry = chainRegistry
    }

    public func createSSSOrigin(
        personOrigin: PersonOrigin,
        period: UInt32,
        seq: UInt32,
        chain: ChainId
    ) async throws -> ExtrinsicOriginDefining {
        let personDeps = try await makePersonDeps(
            personOrigin: personOrigin,
            chain: chain
        )
        let proofContext = SSSSlotContextBuilder.context(period: period, seq: seq)
        let asResourcesOrigin = AsResourcesOriginDefinition(
            input: AsResourcesOriginInput(
                personDeps: personDeps,
                proofContext: proofContext,
                kind: .registerStatementStoreAllowance
            )
        )

        let origin = RestrictsOriginDefinition(enabled: false)

        return ExtrinsicCompoundOrigin(children: [origin, asResourcesOrigin])
    }

    public func createLTSOrigin(
        personOrigin: PersonOrigin,
        period: UInt32,
        counter: UInt8,
        chain: ChainId
    ) async throws -> ExtrinsicOriginDefining {
        let personDeps = try await makePersonDeps(
            personOrigin: personOrigin,
            chain: chain
        )
        let proofContext = BulletinSlotContextBuilder.context(
            period: period,
            counter: counter
        )
        let revision = try await fetchRevision(
            for: personDeps.origin,
            chain: chain
        )

        let asResourcesOrigin = AsResourcesOriginDefinition(
            input: AsResourcesOriginInput(
                personDeps: personDeps,
                proofContext: proofContext,
                kind: .claimLongTermStorage(revision: revision)
            )
        )

        let origin = RestrictsOriginDefinition(enabled: false)

        return ExtrinsicCompoundOrigin(children: [origin, asResourcesOrigin])
    }
}

private extension AsResourcesOriginFactory {
    func makePersonDeps(
        personOrigin: PersonOrigin,
        chain: ChainId
    ) async throws -> PersonProofDependency {
        let connection = try chainRegistry.getRpcConnectionOrError(for: chain)
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chain)

        let proofParamsFetcher = MembershipProofParamsFetcher(
            connection: connection,
            runtimeCodingService: runtimeProvider
        )

        let paramsProvider = RingProofParamsProviderFactory(
            collectionIdentifier: personOrigin.collectionIdentifier,
            proofParamsFetcher: proofParamsFetcher
        ).createProvider(for: personOrigin.ringIndex)

        return PersonProofDependency(
            origin: personOrigin,
            keyManager: personOrigin.keyManager,
            proofParamsFetcher: paramsProvider
        )
    }

    func fetchRevision(
        for origin: PersonOrigin,
        chain: ChainId
    ) async throws -> UInt32 {
        let connection = try chainRegistry.getRpcConnectionOrError(for: chain)
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chain)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        let collectionId = origin.collectionIdentifier

        let ringRoot: MembersPallet.RingRoot? = try await requestFactory
            .queryItems(
                engine: connection,
                keyParams1: { [BytesCodable(wrappedValue: collectionId)] },
                keyParams2: { [StringCodable(wrappedValue: origin.ringIndex)] },
                factory: { codingFactory },
                storagePath: MembersPallet.Storage.root()
            )
            .asyncExecute()
            .first?.value

        return ringRoot?.revision ?? 0
    }
}
