import Foundation
import SubstrateSdk

/// A durable, restart-recoverable top-up. Status is NOT stored here — it is derived from the
/// CoinageTx durability group identified by ``groupId`` (plus detection). The record persists only
/// what cannot be recomputed: the idempotency key, the claim's group, the amount, the secret
/// material needed to drive the claim, and a ``processed`` flag marking the operation complete.
///
/// Material is never wiped — a completed operation keeps everything so its terminal status stays
/// queryable indefinitely (host API contract) and restart recovery can tell processed from active.
public struct IncomingPayment: Equatable, Sendable {
    public let paymentId: IncomingPaymentId
    /// Secret material driving the claim, plus its shape.
    public let source: IncomingPaymentSource
    public let amount: Balance
    /// The CoinageTx durability group the claim registers under; the sole source of truth for status.
    public let groupId: CoinageTxGroupId
    /// Set once the operation reaches a terminal status. `setup()` never starts a task for a
    /// processed record; its presence (not material absence) is the "inactive" signal.
    public let processed: Bool
    public let createdAt: Date

    public init(
        paymentId: IncomingPaymentId,
        source: IncomingPaymentSource,
        amount: Balance,
        groupId: CoinageTxGroupId,
        processed: Bool,
        createdAt: Date
    ) {
        self.paymentId = paymentId
        self.source = source
        self.amount = amount
        self.groupId = groupId
        self.processed = processed
        self.createdAt = createdAt
    }
}

public extension IncomingPayment {
    var sourceType: IncomingPaymentSourceType { source.sourceType }

    /// A payment is active until it is marked ``processed`` on reaching a terminal status.
    var isActive: Bool { !processed }
}
