import Foundation
import Products
import SubstrateSdk

protocol Web3SummitContractRepositoryProtocol {
    func isCheckedIn(productAccountId: AccountId) async throws -> Bool
}

final class Web3SummitContractRepository {
    private let reviveCaller: ReviveContractCalling
    private let chainRegistry: ChainRegistryProtocol
    private let config: Web3SummitConfig

    init(
        reviveCaller: ReviveContractCalling,
        chainRegistry: ChainRegistryProtocol,
        config: Web3SummitConfig
    ) {
        self.reviveCaller = reviveCaller
        self.chainRegistry = chainRegistry
        self.config = config
    }
}

extension Web3SummitContractRepository: Web3SummitContractRepositoryProtocol {
    func isCheckedIn(productAccountId: AccountId) async throws -> Bool {
        let connection = try chainRegistry.getConnectionOrError(for: config.contractChainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: config.contractChainId)

        let address = try Data(productAccountId.keccak256().suffix(20))
        let input = Web3SummitAbi.encodeIsCheckedIn(address: address)

        let output = try await reviveCaller.callReadOnly(
            connection: connection,
            runtimeProvider: runtimeProvider,
            caller: config.dryRunOrigin,
            contract: config.contractAddress,
            input: input
        )

        let decoded = Web3SummitAbi.decodeIsCheckedIn(output: output)

        return decoded ?? false
    }
}
