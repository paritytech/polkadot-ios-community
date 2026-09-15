import Foundation
import SubstrateSdk
@preconcurrency import SubstrateStateCall
import SubstrateStorageQuery
import Operation_iOS
import BigInt

enum ReviveContractError: Error {
    case runtimeApiNotFound
    case callFailed(JSON)
}

struct ReviveContractResult: Decodable {
    let result: Substrate.Result<ReviveExecResult, JSON>
}

/// The pallet's `ContractResult` with the fields a dry-run reads; the dynamic decoder ignores the rest.
struct ReviveDryRunResult: Decodable {
    enum CodingKeys: String, CodingKey {
        case gasRequired = "gas_required"
        case storageDeposit = "storage_deposit"
        case result
    }

    @Substrate.WeightDecodable var gasRequired: Substrate.WeightV2
    let storageDeposit: ReviveStorageDeposit
    let result: Substrate.Result<ReviveExecResult, JSON>
}

enum ReviveStorageDeposit: Decodable {
    case refund(BigUInt)
    case charge(BigUInt)

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let type = try container.decode(String.self)
        let value = try container.decode(StringCodable<BigUInt>.self).wrappedValue

        switch type {
        case "Refund": self = .refund(value)
        case "Charge": self = .charge(value)
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "Unsupported storage deposit \(type)")
            )
        }
    }

    var charged: BigUInt {
        switch self {
        case let .charge(value): value
        case .refund: .zero
        }
    }
}

struct ReviveExecResult: Decodable {
    let flags: ReviveReturnFlags
    let data: BytesCodable

    var output: ReviveExecOutput {
        ReviveExecOutput(flags: flags.bits, data: data.wrappedValue)
    }
}

struct ReviveReturnFlags: Decodable {
    @StringCodable var bits: UInt32
}

final class ReviveContractCaller {
    private let stateCallFactory: StateCallRequestFactoryProtocol
    private let storageRequestFactory: StorageRequestFactoryProtocol

    init(
        stateCallFactory: StateCallRequestFactoryProtocol = StateCallRequestFactory(),
        storageRequestFactory: StorageRequestFactoryProtocol = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: OperationManagerFacade.sharedDefaultQueue)
        )
    ) {
        self.stateCallFactory = stateCallFactory
        self.storageRequestFactory = storageRequestFactory
    }

    // 184467440737090 — max weight dimension (matches the runtime's saturating max used for read calls).
    private static let maxWeight: BigUInt = 184_467_440_737_090

    private static let reviveModule = "Revive"
    private static let originalAccountStorage = StorageCodingPath(moduleName: reviveModule, itemName: "OriginalAccount")
}

extension ReviveContractCaller: ReviveContractCalling {
    func callReadOnly(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        caller: AccountId,
        contract: Data,
        input: Data
    ) async throws -> Data {
        try await callReadOnly(
            connection: connection,
            runtimeProvider: runtimeProvider,
            caller: caller,
            contract: contract,
            input: input,
            at: nil
        ).data
    }

    func callReadOnly(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        caller: AccountId,
        contract: Data,
        input: Data,
        at blockHash: Data?
    ) async throws -> ReviveExecOutput {
        let outcome: ReviveContractResult = try await call(
            connection: connection,
            runtimeProvider: runtimeProvider,
            arguments: CallArguments(caller: caller, contract: contract, input: input),
            at: blockHash
        )

        return try outcome
            .result
            .ensureOkOrError { ReviveContractError.callFailed($0) }
            .output
    }

    func dryRun(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        origin: AccountId,
        contract: Data,
        input: Data
    ) async throws -> ReviveDryRunOutput {
        let outcome: ReviveDryRunResult = try await call(
            connection: connection,
            runtimeProvider: runtimeProvider,
            arguments: CallArguments(caller: origin, contract: contract, input: input),
            at: nil
        )

        let output = try outcome.result.ensureOkOrError { ReviveContractError.callFailed($0) }.output

        return ReviveDryRunOutput(
            output: output,
            weightRequired: outcome.gasRequired,
            storageDeposit: outcome.storageDeposit.charged
        )
    }

    func isAccountMapped(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        account: AccountId
    ) async throws -> Bool {
        let evmAccount = try account.keccak256().suffix(20)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        let responses: [StorageResponse<BytesCodable>] = try await storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: evmAccount)] },
            factory: { codingFactory },
            storagePath: Self.originalAccountStorage,
            options: StorageQueryListOptions()
        )
        .asyncExecute()

        return responses.first?.value != nil
    }
}

private extension ReviveContractCaller {
    // Manually SCALE-encode the ReviveApi_call parameters (in order):
    // origin: AccountId32, dest: H160, value: u128, gas_limit: Weight,
    // storage_deposit_limit: u128, input_data: Vec<u8>.
    struct CallArguments {
        let caller: AccountId
        let contract: Data
        let input: Data
    }

    func call<Outcome: Decodable>(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        arguments: CallArguments,
        at blockHash: Data?
    ) async throws -> Outcome {
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        guard
            let runtimeApi = codingFactory.metadata.getRuntimeApiMethod(
                for: "ReviveApi",
                methodName: "call"
            ) else {
            throw ReviveContractError.runtimeApiNotFound
        }

        return try await stateCallFactory.createWrapper(
            for: runtimeApi.callName,
            paramsClosure: { encoder, context in
                try Self.encodeCallParams(
                    encoder: encoder,
                    context: context,
                    runtimeApi: runtimeApi,
                    arguments: arguments
                )
            },
            codingFactoryClosure: { codingFactory },
            connection: connection,
            queryType: runtimeApi.method.output.asTypeId(),
            at: blockHash?.toHex(includePrefix: true)
        )
        .asyncExecute()
    }

    static func encodeCallParams(
        encoder: DynamicScaleEncoding,
        context: RuntimeJsonContext,
        runtimeApi: RuntimeApiQueryResult,
        arguments: CallArguments
    ) throws {
        let rawContext = context.toRawContext()
        let inputs = runtimeApi.method.inputs

        try encoder.append(
            BytesCodable(wrappedValue: arguments.caller),
            ofType: inputs[0].paramType.asTypeId(),
            with: rawContext
        )
        try encoder.append(
            BytesCodable(wrappedValue: arguments.contract),
            ofType: inputs[1].paramType.asTypeId(),
            with: rawContext
        )
        try encoder.append(
            StringCodable(wrappedValue: BigUInt.zero),
            ofType: inputs[2].paramType.asTypeId(),
            with: rawContext
        )

        let weight = Substrate.WeightV2(refTime: maxWeight, proofSize: maxWeight)
        try encoder.append(weight, ofType: inputs[3].paramType.asTypeId(), with: rawContext)

        try encoder.append(
            StringCodable(wrappedValue: maxWeight),
            ofType: inputs[4].paramType.asTypeId(),
            with: rawContext
        )
        try encoder.append(
            BytesCodable(wrappedValue: arguments.input),
            ofType: inputs[5].paramType.asTypeId(),
            with: rawContext
        )
    }
}
