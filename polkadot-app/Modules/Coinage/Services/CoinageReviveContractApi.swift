import ChainRegistry
import Coinage
import Foundation
import SubstrateSdk

/// Coinage's ``ReviveContractApiProtocol`` over the app's revive caller, with the chain fixed to the
/// one the `AccountDataStore` contract lives on (Asset Hub).
final class CoinageReviveContractApi: ReviveContractApiProtocol, @unchecked Sendable {
    private let chainId: ChainModel.Id
    private let chainRegistry: ChainRegistryProtocol
    private let caller: ReviveContractCalling

    init(
        chainId: ChainModel.Id,
        chainRegistry: ChainRegistryProtocol,
        caller: ReviveContractCalling = ReviveContractCaller()
    ) {
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.caller = caller
    }

    func callReadOnly(contract: Data, input: Data, at blockHash: Data?) async throws -> Data {
        let output = try await caller.callReadOnly(
            connection: chainRegistry.getConnectionOrError(for: chainId),
            runtimeProvider: chainRegistry.getRuntimeProviderOrError(for: chainId),
            caller: AppConfig.reviveAccountId,
            contract: contract,
            input: input,
            at: blockHash
        )
        return try Self.ensureNotReverted(output).data
    }

    func dryRun(origin: AccountId, contract: Data, input: Data) async throws -> ReviveDryRun {
        let dryRun = try await caller.dryRun(
            connection: chainRegistry.getConnectionOrError(for: chainId),
            runtimeProvider: chainRegistry.getRuntimeProviderOrError(for: chainId),
            origin: origin,
            contract: contract,
            input: input
        )
        let output = try Self.ensureNotReverted(dryRun.output)

        return ReviveDryRun(
            data: output.data,
            weightRequired: dryRun.weightRequired,
            storageDeposit: dryRun.storageDeposit
        )
    }

    func isAccountMapped(_ account: AccountId) async throws -> Bool {
        try await caller.isAccountMapped(
            connection: chainRegistry.getConnectionOrError(for: chainId),
            runtimeProvider: chainRegistry.getRuntimeProviderOrError(for: chainId),
            account: account
        )
    }
}

private extension CoinageReviveContractApi {
    static func ensureNotReverted(_ output: ReviveExecOutput) throws -> ReviveExecOutput {
        guard !output.isReverted else {
            throw ReviveContractRevertedError(data: output.data)
        }
        return output
    }
}
