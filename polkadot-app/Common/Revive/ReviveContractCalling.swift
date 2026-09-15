import BigInt
import Foundation
import SubstrateSdk

/// What a contract execution returned: the revert flag and the output bytes.
struct ReviveExecOutput: Equatable {
    static let revertFlag: UInt32 = 0x1

    let flags: UInt32
    let data: Data

    var isReverted: Bool { flags & Self.revertFlag != 0 }
}

/// A simulated call: its output and the limits a real call must declare.
struct ReviveDryRunOutput: Equatable {
    let output: ReviveExecOutput
    let weightRequired: Substrate.WeightV2
    /// The deposit the call would charge; zero when it would only refund.
    let storageDeposit: BigUInt
}

protocol ReviveContractCalling: Sendable {
    func callReadOnly(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        caller: AccountId,
        contract: Data,
        input: Data
    ) async throws -> Data

    /// Evaluates a read-only call against the state at `blockHash`, or at the node's latest block
    /// when nil, returning the output together with its revert flag.
    func callReadOnly(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        caller: AccountId,
        contract: Data,
        input: Data,
        at blockHash: Data?
    ) async throws -> ReviveExecOutput

    /// Simulates `input` as `origin` would send it, reporting the weight and deposit a real call needs.
    func dryRun(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        origin: AccountId,
        contract: Data,
        input: Data
    ) async throws -> ReviveDryRunOutput

    /// Whether `account` has an H160 the pallet recognises as its own (`Revive.OriginalAccount`).
    func isAccountMapped(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        account: AccountId
    ) async throws -> Bool
}
