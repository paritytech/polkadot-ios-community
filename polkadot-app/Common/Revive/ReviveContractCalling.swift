import Foundation
import SubstrateSdk

protocol ReviveContractCalling {
    func callReadOnly(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        caller: AccountId,
        contract: Data,
        input: Data
    ) async throws -> Data
}
