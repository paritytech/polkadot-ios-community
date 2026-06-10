import Foundation
import BigInt
import ExtrinsicService
import NovaCrypto
import Operation_iOS
import Products
import SubstrateSdk
import KeyDerivation

enum PolkadotHostSigningResult {
    case signedPayload(signature: Data, signedTransaction: Data?)
    case rawSignature(signature: Data)
    case signedTransaction(encodedTransaction: Data)
}

protocol PolkadotSignatureMaking {
    func makeSignature(
        result: PolkadotParsedSigningRequestResult,
        chainRegistry: ChainRegistryProtocol
    ) async throws -> PolkadotHostSigningResult
}

final class PolkadotSignatureFactory {
    private let extensionsFactory: ExtrinsicTransactionExtensionMaking
    private let extrinsicVersionProvider: ExtrinsicVersionProviding

    init(
        extensionsFactory: ExtrinsicTransactionExtensionMaking = ExtrinsicTransactionExtensionFactory(),
        extrinsicVersionProvider: ExtrinsicVersionProviding = ExtrinsicVersionProvider()
    ) {
        self.extensionsFactory = extensionsFactory
        self.extrinsicVersionProvider = extrinsicVersionProvider
    }
}

extension PolkadotSignatureFactory: PolkadotSignatureMaking {
    func makeSignature(
        result: PolkadotParsedSigningRequestResult,
        chainRegistry: ChainRegistryProtocol
    ) async throws -> PolkadotHostSigningResult {
        switch result.parsedRequest {
        case let .legacyTransaction(transaction):
            let (builder, codingFactory) = try await makeLegacyTransactionBuilder(
                transaction,
                result: result,
                chainRegistry: chainRegistry
            )
            return try buildLegacyTransactionResult(
                using: builder,
                for: result,
                codingFactory: codingFactory,
                withSignedTransaction: transaction.withSignedTransaction
            )
        case let .rawBytes(data):
            return try buildRawSignatureResult(for: result, rawBytes: data)
        case let .createTransaction(createTx):
            let (builder, codingFactory) = try await makeCreateTransactionBuilder(
                createTx,
                result: result,
                chainRegistry: chainRegistry
            )
            return try buildCreateTransactionResult(
                using: builder,
                for: result,
                codingFactory: codingFactory,
                hasDisabledVerifySignature: createTx.resolvedExtensions.existingParameters
                    .contains(.disabledVerifySignature)
            )
        }
    }
}

// MARK: - Legacy Transaction Builder

private extension PolkadotSignatureFactory {
    func makeLegacyTransactionBuilder(
        _ transaction: PolkadotLegacyTransaction,
        result: PolkadotParsedSigningRequestResult,
        chainRegistry: ChainRegistryProtocol
    ) async throws -> (ExtrinsicBuilderProtocol, RuntimeCoderFactoryProtocol) {
        let extrinsicVersion = Extrinsic.Version.V4
        let genesisHash = transaction.genesisHash.withoutHexPrefix()

        guard let chain = chainRegistry.getChainByGenesis(for: genesisHash) else {
            throw PolkadotSigningError.missingChain
        }

        let codingFactory = try await chainRegistry
            .getRuntimeProviderOrError(for: chain.chainId)
            .fetchCoderFactoryOperation()
            .asyncExecute()

        var builder = ExtrinsicBuilder(
            extrinsicVersion: extrinsicVersion,
            specVersion: transaction.specVersion,
            transactionVersion: transaction.transactionVersion,
            genesisHash: genesisHash
        )
        .with(runtimeJsonContext: codingFactory.createRuntimeJsonContext())
        .with(nonce: transaction.nonce)
        .with(era: transaction.era, blockHash: transaction.blockHash)

        let accountId = try result.wallet.getRawPublicKey()

        builder = try builder.with(address: MultiAddress.accoundId(accountId))

        if let metadataHash = transaction.metadataHash {
            builder = builder.with(metadataHash: metadataHash)
        }

        switch transaction.call {
        case let .raw(bytes):
            builder = try builder.adding(rawCall: bytes)
        case let .callable(value):
            builder = try builder.adding(call: value)
        }

        if transaction.tip > 0 {
            builder = builder.with(tip: transaction.tip)
        }

        for appExtension in extensionsFactory.createExtensions() {
            builder = builder.adding(transactionExtension: appExtension)
        }

        return (builder, codingFactory)
    }
}

// MARK: - Create Transaction Builder

private extension PolkadotSignatureFactory {
    func makeCreateTransactionBuilder(
        _ createTransaction: PolkadotParsedCreateTransaction,
        result: PolkadotParsedSigningRequestResult,
        chainRegistry: ChainRegistryProtocol
    ) async throws -> (ExtrinsicBuilderProtocol, RuntimeCoderFactoryProtocol) {
        let resolved = createTransaction.resolvedExtensions

        guard let chain = chainRegistry.getChainByGenesis(for: createTransaction.genesisHash) else {
            throw PolkadotSigningError.missingChain
        }

        let connection = try chainRegistry.getConnectionOrError(for: chain.chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chain.chainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        let extrinsicVersion = extrinsicVersionProvider.getExtrinsicVersion(
            for: chain.chainId,
            isSigned: true
        )

        var builder: ExtrinsicBuilderProtocol = ExtrinsicBuilder(
            extrinsicVersion: extrinsicVersion,
            specVersion: codingFactory.specVersion,
            transactionVersion: codingFactory.txVersion,
            genesisHash: createTransaction.genesisHash
        )
        .with(runtimeJsonContext: codingFactory.createRuntimeJsonContext())

        let accountId = try result.wallet.getRawPublicKey()

        switch extrinsicVersion {
        case .V4:
            builder = try builder.with(address: MultiAddress.accoundId(accountId))
        case .V5:
            builder = try builder.with(address: BytesCodable(wrappedValue: accountId))
        }

        builder = try await fillNonceIfNeeded(
            builder: builder,
            existingParameters: resolved.existingParameters,
            accountId: accountId,
            chain: chain,
            connection: connection
        )

        builder = try await fillMortalityIfNeeded(
            builder: builder,
            existingParameters: resolved.existingParameters,
            chain: chain,
            connection: connection,
            runtimeService: runtimeProvider
        )

        builder = try builder.adding(rawCall: createTransaction.callData)

        // App extensions first, then resolved ones override
        for appExtension in extensionsFactory.createExtensions() {
            builder = builder.adding(transactionExtension: appExtension)
        }

        for customExtension in resolved.customExtensions {
            builder = builder.adding(transactionExtension: customExtension)
        }

        return (builder, codingFactory)
    }
}

// MARK: - Gap Filling

private extension PolkadotSignatureFactory {
    func fillNonceIfNeeded(
        builder: ExtrinsicBuilderProtocol,
        existingParameters: CreateTransactionPayloadExtensions.ExistingParameters,
        accountId: Data,
        chain: ChainProtocol,
        connection: JSONRPCEngine
    ) async throws -> ExtrinsicBuilderProtocol {
        guard !existingParameters.contains(.nonce) else { return builder }

        let nonce = try await fetchNonce(
            accountId: accountId,
            chain: chain,
            connection: connection
        )

        return builder.with(nonce: nonce)
    }

    func fillMortalityIfNeeded(
        builder: ExtrinsicBuilderProtocol,
        existingParameters: CreateTransactionPayloadExtensions.ExistingParameters,
        chain: ChainModel,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol
    ) async throws -> ExtrinsicBuilderProtocol {
        guard !existingParameters.contains(.mortality) else { return builder }

        let eraParams = try await fetchEraParameters(
            chain: chain,
            connection: connection,
            runtimeService: runtimeService
        )

        let blockHash = try await fetchBlockHash(
            blockNumber: eraParams.blockNumber,
            connection: connection
        )

        return builder.with(era: eraParams.extrinsicEra, blockHash: blockHash)
    }
}

// MARK: - Chain Data Fetching

private extension PolkadotSignatureFactory {
    func fetchNonce(
        accountId: Data,
        chain: ChainProtocol,
        connection: JSONRPCEngine
    ) async throws -> UInt32 {
        let factory = SubstrateNonceOperationFactory(
            chain: chain,
            connection: connection,
            timeout: JSONRPCTimeout.singleNode
        )

        let wrapper = factory.createWrapper(for: { accountId })
        return try await wrapper.asyncExecute()
    }

    func fetchEraParameters(
        chain: ChainModel,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol
    ) async throws -> ExtrinsicEraParameters {
        let factory = MortalEraOperationFactory(chain: chain)
        let wrapper = factory.createOperation(
            from: connection,
            runtimeService: runtimeService
        )
        return try await wrapper.asyncExecute()
    }

    func fetchBlockHash(
        blockNumber: BlockNumber,
        connection: JSONRPCEngine
    ) async throws -> String {
        let factory = BlockHashOperationFactory()
        let operation = factory.createBlockHashOperation(
            connection: connection,
            for: { blockNumber }
        )
        return try await operation.asyncExecute()
    }
}

// MARK: - Result Building

private extension PolkadotSignatureFactory {
    func makeTypedSignature(
        from rawSignature: Data,
        codingFactory: RuntimeCoderFactoryProtocol
    ) throws -> Data {
        let signature = MultiSignature.sr25519(data: rawSignature)
        let signatureEncoder = codingFactory.createEncoder()

        try signatureEncoder.append(
            signature,
            ofType: KnownType.signature.name,
            with: codingFactory.createRuntimeJsonContext().toRawContext()
        )

        return try signatureEncoder.encode()
    }

    func buildLegacyTransactionResult(
        using builder: ExtrinsicBuilderProtocol,
        for result: PolkadotParsedSigningRequestResult,
        codingFactory: RuntimeCoderFactoryProtocol,
        withSignedTransaction: Bool
    ) throws -> PolkadotHostSigningResult {
        let signer = DefaultSigningWrapper(secretProvider: result.wallet)
        let signerProvider = try SNPublicKey(rawData: result.wallet.getRawPublicKey())

        let context = SigningContext.SubstrateExtrinsic(
            signerProvider: signerProvider,
            extrinsicMemo: builder.makeMemo(),
            codingFactory: codingFactory
        )

        let rawSignature = try builder.buildRawSignature(
            using: { try signer.sign($0, context: .substrateExtrinsic(context)).rawData() },
            encodingFactory: codingFactory,
            metadata: codingFactory.metadata
        )

        let typedSignature = try makeTypedSignature(
            from: rawSignature,
            codingFactory: codingFactory
        )

        let signedTransaction: Data? =
            if withSignedTransaction {
                // we need to resign transaction and build since implication from rawSignature may differ
                try builder.signing(
                    by: { try signer.sign($0, context: .substrateExtrinsic(context)).rawData() },
                    of: .sr25519,
                    using: codingFactory,
                    metadata: codingFactory.metadata
                )
                .build(
                    using: codingFactory,
                    metadata: codingFactory.metadata
                )
            } else {
                nil
            }

        return .signedPayload(signature: typedSignature, signedTransaction: signedTransaction)
    }

    func buildRawSignatureResult(
        for result: PolkadotParsedSigningRequestResult,
        rawBytes: Data
    ) throws -> PolkadotHostSigningResult {
        let signer = DefaultSigningWrapper(secretProvider: result.wallet)
        let signerProvider = try SNPublicKey(rawData: result.wallet.getRawPublicKey())
        let rawSignature = try signer.sign(rawBytes, context: .rawBytes(signerProvider)).rawData()
        return .rawSignature(signature: rawSignature)
    }

    func buildCreateTransactionResult(
        using builder: ExtrinsicBuilderProtocol,
        for result: PolkadotParsedSigningRequestResult,
        codingFactory: RuntimeCoderFactoryProtocol,
        hasDisabledVerifySignature: Bool
    ) throws -> PolkadotHostSigningResult {
        let encodedTransaction: Data

        if hasDisabledVerifySignature {
            encodedTransaction = try builder.build(
                using: codingFactory,
                metadata: codingFactory.metadata
            )
        } else {
            let signer = DefaultSigningWrapper(secretProvider: result.wallet)
            let signerProvider = try SNPublicKey(rawData: result.wallet.getRawPublicKey())

            let context = SigningContext.SubstrateExtrinsic(
                signerProvider: signerProvider,
                extrinsicMemo: builder.makeMemo(),
                codingFactory: codingFactory
            )

            encodedTransaction = try builder.signing(
                by: { try signer.sign($0, context: .substrateExtrinsic(context)).rawData() },
                of: .sr25519,
                using: codingFactory,
                metadata: codingFactory.metadata
            )
            .build(
                using: codingFactory,
                metadata: codingFactory.metadata
            )
        }

        return .signedTransaction(encodedTransaction: encodedTransaction)
    }
}
