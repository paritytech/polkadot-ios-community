import Foundation
import SubstrateSdk
import Products

// Implementation of DotNsContractApiProtocol that calls the Revive pallet on Asset Hub.
final class ReviveDotNsContractApi {
    private let connection: JSONRPCEngine
    private let runtimeProvider: RuntimeCodingServiceProtocol
    private let config: DotNsConfig
    private let caller: ReviveContractCalling

    init(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        config: DotNsConfig,
        caller: ReviveContractCalling = ReviveContractCaller()
    ) {
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.config = config
        self.caller = caller
    }
}

private extension ReviveDotNsContractApi {
    func callReviveContract(inputData: Data) async throws -> Data {
        let origin = AppConfig.reviveAccountId

        return try await caller.callReadOnly(
            connection: connection,
            runtimeProvider: runtimeProvider,
            caller: origin,
            contract: config.resolverContractAddress,
            input: inputData
        )
    }
}

extension ReviveDotNsContractApi: DotNsContractApiProtocol {
    func resolveContentHash(dotNsName: String) async throws -> Data {
        let node = try NameHash.nameHash(dotNsName)
        let callData = DotNsAbi.encodeContentHash(node: node)

        let outputBytes = try await callReviveContract(inputData: callData)

        guard !outputBytes.isEmpty else {
            throw DotNsContractError.contentHashNotFound
        }

        guard let contentHash = DotNsAbi.decodeContentHash(output: outputBytes) else {
            throw DotNsContractError.contentHashNotFound
        }

        return try Eip1577.stripPrefix(contentHash)
    }

    func getMetadata(dotNsName: String, key: String) async throws -> String? {
        let node = try NameHash.nameHash(dotNsName)
        let callData = DotNsAbi.encodeText(node: node, key: key)

        let outputBytes = try await callReviveContract(inputData: callData)

        guard !outputBytes.isEmpty else { return nil }

        return DotNsAbi.decodeText(output: outputBytes)
    }
}
