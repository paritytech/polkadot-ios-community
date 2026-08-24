import Foundation

/// What a handed-off coin's payment is doing, from the sender's point of view.
public enum CoinPaymentStatus: Sendable, Equatable {
    /// The coin was never minted, so the key we gave away controls nothing.
    case failed
    /// Minted and still unclaimed.
    case awaitingClaim
    /// Gone, and the peer took it.
    case claimed
    /// Not enough is known yet.
    case detecting
}

/// Appendix A, evaluated on demand using the best (highest) head.
///
/// Nothing here is stored: each answer is a query over the entry set plus one presence read.
/// The use of the best head (rather than finalized) means detection latency is minimized for
/// payment-facing status, but `Awaiting claim` is reorg-able and must never be treated as
/// terminal by a caller gating an irreversible action. Only `Claimed` and `Failed` are safe
/// to act on — those are gated on ``EntryStatus``, which is only set from the finalized view.
public struct PaymentStatusQuery {
    private let store: any DurabilityStoring
    private let chain: any DurabilityChainReading

    public init(store: any DurabilityStoring, chain: any DurabilityChainReading) {
        self.store = store
        self.chain = chain
    }

    /// Status table keyed on presence at the best head and minter status.
    ///
    /// | Presence at B | Minter status | Result |
    /// |---|---|---|
    /// | present | any | Awaiting claim |
    /// | absent | pending or pendingSuccess | Detecting |
    /// | absent | failure | Failed |
    /// | absent | finalizedSuccess | Claimed |
    /// | absent | no minter | Detecting |
    public func status(of coin: OwnAsset, view: ChainView) async throws -> CoinPaymentStatus {
        let minter = try await store.minter(of: coin)
        let atBest = await chain.readOutputs([coin], at: view.best).first ?? .failedRead

        // Present at best head: always awaiting claim, regardless of minter status.
        if atBest.isPresent {
            return .awaitingClaim
        }

        // Failed read: absence is not proven, so no verdict can be terminal.
        // Only a proven absence may reach the minter status check below.
        if atBest.isFailedRead {
            return .detecting
        }

        // Absent: decision depends on minter status.
        switch minter?.status {
        case .failure:
            return .failed
        case .finalizedSuccess:
            return .claimed
        case .pending,
             .pendingSuccess:
            return .detecting
        case nil:
            return .detecting
        }
    }
}
