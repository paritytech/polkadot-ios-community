import Foundation
import ExtrinsicService
import SubstrateSdk
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
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chain)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        let networkSuffix = try await codingFactory.readNetworkSuffix(
            for: ResourcesPallet.Constants.suffix()
        )
        let proofContext = try ProductContextSuffix
            .statementStoreSlot(period: period, seq: seq)
            .context(networkSuffix: networkSuffix)
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
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chain)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        let networkSuffix = try await codingFactory.readNetworkSuffix(
            for: ResourcesPallet.Constants.suffix()
        )
        let proofContext = try ProductContextSuffix
            .longTermStorage(period: period, counter: counter)
            .context(networkSuffix: networkSuffix)

        let asResourcesOrigin = AsResourcesOriginDefinition(
            input: AsResourcesOriginInput(
                personDeps: personDeps,
                proofContext: proofContext,
                kind: .claimLongTermStorage
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
}
