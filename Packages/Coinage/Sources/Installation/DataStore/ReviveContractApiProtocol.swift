import BigInt
import Foundation
import SubstrateSdk

/// What a contract call would do if `origin` sent it now: its output and the limits a real call must
/// declare.
public struct ReviveDryRun: Equatable, Sendable {
    public let data: Data
    public let weightRequired: Substrate.WeightV2
    /// The deposit the call would charge; zero when it would only refund.
    public let storageDeposit: BigUInt

    public init(data: Data, weightRequired: Substrate.WeightV2, storageDeposit: BigUInt) {
        self.data = data
        self.weightRequired = weightRequired
        self.storageDeposit = storageDeposit
    }
}

/// The contract ran and reverted; `data` is what it returned as the reason.
public struct ReviveContractRevertedError: Error, Equatable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

/// Coinage's view of pallet-revive on the chain the `AccountDataStore` contract lives on. The app
/// implements it over its revive caller with the chain fixed.
public protocol ReviveContractApiProtocol: Sendable {
    /// Evaluates a read-only call against the state at `blockHash`, or at the node's latest block when
    /// nil. A revert fails with ``ReviveContractRevertedError``.
    func callReadOnly(contract: Data, input: Data, at blockHash: Data?) async throws -> Data

    /// Simulates `input` as `origin` would send it. A revert fails with ``ReviveContractRevertedError``.
    /// The origin matters: limits simulated from any other account describe a different call.
    func dryRun(origin: AccountId, contract: Data, input: Data) async throws -> ReviveDryRun

    /// Whether `account` has an H160 the pallet recognises as its own. An unmapped origin is rejected by
    /// every contract call, and a dry-run cannot tell: the pallet maps the origin for the length of the
    /// simulation.
    func isAccountMapped(_ account: AccountId) async throws -> Bool
}
