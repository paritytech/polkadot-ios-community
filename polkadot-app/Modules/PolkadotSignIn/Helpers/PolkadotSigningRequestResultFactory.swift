import Foundation
import Products
import SubstrateSdk
import KeyDerivation
import BigInt

protocol PolkadotSigningRequestResultMaking {
    func makeParsedResult(
        signingContext: PolkadotSigningContextProtocol
    ) async throws -> PolkadotParsedSigningRequestResult
}

final class PolkadotSigningRequestResultFactory {
    private let chainRegistry: ChainRegistryProtocol
    private let jsonPrinter: JSONPrettyPrinting
    private let extensionResolver: CreateTransactionExtensionResolver

    init(
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        jsonPrinter: JSONPrettyPrinting = ExtrinsicJSONProcessor(),
        extensionResolver: CreateTransactionExtensionResolver = CreateTransactionExtensionResolver()
    ) {
        self.chainRegistry = chainRegistry
        self.jsonPrinter = jsonPrinter
        self.extensionResolver = extensionResolver
    }
}

extension PolkadotSigningRequestResultFactory: PolkadotSigningRequestResultMaking {
    func makeParsedResult(
        signingContext: PolkadotSigningContextProtocol
    ) async throws -> PolkadotParsedSigningRequestResult {
        let requester = signingContext.requester

        switch signingContext.signingModel {
        case let .signingRequest(request):
            return try await makeParsedSigningRequest(
                request: request,
                requester: requester,
                signingContext: signingContext
            )
        case let .createTransaction(payload):
            return try await makeParsedCreateTransaction(
                payload: payload,
                requester: requester,
                signingContext: signingContext
            )
        }
    }
}

private extension PolkadotSigningRequestResultFactory {
    func makeParsedSigningRequest(
        request: PolkadotHostRemoteMessage.SigningRequest,
        requester: PolkadotSigningRequester,
        signingContext: PolkadotSigningContextProtocol
    ) async throws -> PolkadotParsedSigningRequestResult {
        switch request {
        case let .transaction(transaction):
            try await makeParsedLegacyTransaction(
                transaction: transaction,
                requester: requester,
                signingContext: signingContext
            )
        case let .rawPayload(rawPayload):
            try makeParsedRawDataResult(
                rawPayload: rawPayload,
                requester: requester,
                signingContext: signingContext
            )
        }
    }

    func makeParsedLegacyTransaction(
        transaction: SignTransactionPayload,
        requester: PolkadotSigningRequester,
        signingContext: PolkadotSigningContextProtocol
    ) async throws -> PolkadotParsedSigningRequestResult {
        let genesisHash = transaction.genesisHash.toHex()

        guard let chain = chainRegistry.getChainByGenesis(for: genesisHash) else {
            throw PolkadotSigningError.missingChain
        }

        guard
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chain.chainId),
            let codingFactory = try? await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        else {
            throw PolkadotSigningError.missingRuntimeProvider
        }

        let wallet = try signingContext.resolveWallet(for: transaction.account)

        let call = try makeCall(
            codingFactory: codingFactory,
            transaction: transaction
        )

        let displayAddress = try makeDisplayAddress(for: wallet)

        let parsedTransaction = try PolkadotLegacyTransaction(
            address: displayAddress,
            blockHash: transaction.blockHash.toHex(),
            blockNumber: makeNumber(hexString: transaction.blockNumber.toHex()),
            era: makeEra(transaction: transaction),
            genesisHash: genesisHash,
            call: call,
            nonce: UInt32(makeNumber(hexString: transaction.nonce.toHex())),
            specVersion: UInt32(makeNumber(hexString: transaction.specVersion.toHex())),
            tip: makeNumber(hexString: transaction.tip.toHex()),
            transactionVersion: UInt32(makeNumber(hexString: transaction.transactionVersion.toHex())),
            metadataHash: transaction.metadataHash,
            assetId: nil,
            withSignedTransaction: transaction.withSignedTransaction ?? false,
            signedExtensions: transaction.signedExtensions,
            version: makeVersion(transaction: transaction)
        )

        let detailsText = try makeDetailsText(
            parsedTransaction: parsedTransaction,
            codingFactory: codingFactory
        )

        return PolkadotParsedSigningRequestResult(
            wallet: wallet,
            parsedRequest: .legacyTransaction(parsedTransaction),
            requester: requester,
            detailsText: detailsText
        )
    }

    func makeDisplayAddress(for wallet: WalletManaging) throws -> AccountAddress {
        try wallet.getRawPublicKey().toAddress(using: .genericFormat)
    }

    func makeCall(
        codingFactory: RuntimeCoderFactoryProtocol,
        transaction: SignTransactionPayload
    ) throws -> PolkadotParsedTransactionCall {
        let methodDecoder = try codingFactory.createDecoder(from: transaction.method)

        if let callableMethod: RuntimeCall<JSON> = try? methodDecoder.read(
            of: KnownType.call.name,
            with: codingFactory.createRuntimeJsonContext().toRawContext()
        ) {
            return .callable(value: callableMethod)
        } else {
            return .raw(bytes: transaction.method)
        }
    }

    func makeEra(
        transaction: SignTransactionPayload
    ) throws -> Era {
        let decoder = try ScaleDecoder(data: transaction.era)
        return try Era(scaleDecoder: decoder)
    }

    func makeVersion(
        transaction: SignTransactionPayload
    ) throws -> PolkadotLegacyTransaction.Version {
        switch transaction.version {
        case 4: return .version4
        case 5: return .version5
        default: throw PolkadotSigningError.invalidVersion
        }
    }

    func makeNumber(hexString: String) throws -> BigUInt {
        guard let number = BigUInt.fromHexString(hexString) else {
            throw PolkadotSigningError.invalidNumberInHex
        }
        return number
    }

    func makeDetailsText(
        parsedTransaction: PolkadotLegacyTransaction,
        codingFactory: RuntimeCoderFactoryProtocol
    ) throws -> String {
        let detailsJSON = try parsedTransaction.toScaleCompatibleJSON(
            with: codingFactory.createRuntimeJsonContext().toRawContext()
        )
        return try jsonPrinter.prettyPrintedString(from: detailsJSON)
    }

    func makeParsedCreateTransaction(
        payload: CreateTransactionPayload<ProductAccountId>,
        requester: PolkadotSigningRequester,
        signingContext: PolkadotSigningContextProtocol
    ) async throws -> PolkadotParsedSigningRequestResult {
        let genesisHash = payload.genesisHash.toHex()

        guard let chain = chainRegistry.getChainByGenesis(for: genesisHash) else {
            throw PolkadotSigningError.missingChain
        }

        guard
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chain.chainId),
            let codingFactory = try? await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        else {
            throw PolkadotSigningError.missingRuntimeProvider
        }

        let wallet = try signingContext.resolveWallet(for: payload.signer)
        let resolved = try extensionResolver.resolve(
            extensions: payload.extensions,
            codingFactory: codingFactory
        )

        let call = try makeCall(codingFactory: codingFactory, callData: payload.callData)

        let parsedCreateTx = PolkadotParsedCreateTransaction(
            signer: payload.signer,
            callData: payload.callData,
            call: call,
            resolvedExtensions: resolved,
            genesisHash: genesisHash,
            txExtVersion: payload.txExtVersion
        )

        let detailsText = try makeCreateTransactionDetailsText(
            call: call,
            codingFactory: codingFactory
        )

        return PolkadotParsedSigningRequestResult(
            wallet: wallet,
            parsedRequest: .createTransaction(parsedCreateTx),
            requester: requester,
            detailsText: detailsText
        )
    }

    func makeCall(
        codingFactory: RuntimeCoderFactoryProtocol,
        callData: Data
    ) throws -> PolkadotParsedTransactionCall {
        let methodDecoder = try codingFactory.createDecoder(from: callData)

        if let callableMethod: RuntimeCall<JSON> = try? methodDecoder.read(
            of: KnownType.call.name,
            with: codingFactory.createRuntimeJsonContext().toRawContext()
        ) {
            return .callable(value: callableMethod)
        } else {
            return .raw(bytes: callData)
        }
    }

    func makeCreateTransactionDetailsText(
        call: PolkadotParsedTransactionCall,
        codingFactory: RuntimeCoderFactoryProtocol
    ) throws -> String {
        let callJSON: JSON =
            switch call {
            case let .raw(bytes):
                .stringValue(bytes.toHex(includePrefix: true))
            case let .callable(value):
                try value.toScaleCompatibleJSON(
                    with: codingFactory.createRuntimeJsonContext().toRawContext()
                )
            }

        return try jsonPrinter.prettyPrintedString(from: callJSON)
    }

    func makeParsedRawDataResult(
        rawPayload: PolkadotHostRemoteMessage.SigningRawPayload,
        requester: PolkadotSigningRequester,
        signingContext: PolkadotSigningContextProtocol
    ) throws -> PolkadotParsedSigningRequestResult {
        let wallet = try signingContext.resolveWallet(for: rawPayload.account)

        let rawBytes = try makeRawBytes(rawPayload: rawPayload)
        let detailsText = rawBytes.toHex(includePrefix: true)

        return PolkadotParsedSigningRequestResult(
            wallet: wallet,
            parsedRequest: .rawBytes(rawBytes),
            requester: requester,
            detailsText: detailsText
        )
    }

    func makeRawBytes(
        rawPayload: PolkadotHostRemoteMessage.SigningRawPayload
    ) throws -> Data {
        switch rawPayload.type {
        case let .bytes(data):
            data
        case let .payload(string):
            try makeRawBytes(string: string)
        }
    }

    func makeRawBytes(string: String) throws -> Data {
        let message = try makeSerializedMessage(string: string)
        return try makeWrappedMessage(message: message)
    }

    func makeSerializedMessage(string: String) throws -> Data {
        guard !string.isHex() else {
            return try Data(hexString: string)
        }
        guard let data = string.data(using: .utf8) else {
            throw PolkadotSigningError.rawDataCorrupted
        }
        return data
    }

    func makeWrappedMessage(message: Data) throws -> Data {
        let prefix = "<Bytes>"
        let suffix = "</Bytes>"

        guard
            let suffixData = suffix.data(using: .ascii),
            let prefixData = prefix.data(using: .ascii)
        else {
            throw PolkadotSigningError.rawDataCorrupted
        }

        if message.prefix(prefixData.count) == prefixData,
           message.suffix(suffixData.count) == suffixData {
            return message
        }

        return prefixData + message + suffixData
    }
}
