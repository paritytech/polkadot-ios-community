import BigInt
import Coinage
import Foundation
import SubstrateSdk

extension CoinageTransferDetection {
    /// A chat claim only gives up after its retry window, so a give-up always reads as expired.
    /// `claimingRest` is plain `claiming`: the claimed-so-far amount is deliberately not persisted.
    /// `claimedPartially` is a verdict reached only after every claim entry settled, so it is final.
    var incomingState: IncomingTransferState {
        switch self {
        case .detecting:
            IncomingTransferState(status: .detecting)
        case .claiming,
             .claimingRest:
            IncomingTransferState(status: .claiming)
        case let .claimed(amount, finalized):
            IncomingTransferState(status: finalized ? .claimedFinalized : .claimed, actualValue: amount)
        case let .claimedPartially(claimed):
            IncomingTransferState(status: .claimedFinalized, actualValue: claimed)
        case .notClaimed:
            IncomingTransferState(status: .returnedToSender)
        }
    }
}

extension [PublicKey: CoinageTransferState] {
    /// Mirrors Android's `toPaymentStatus`: any coin still to be taken keeps the message at
    /// `sending`/`sent`; once nothing is outstanding, the claimed value is final. The finalized
    /// variants are reached only when every coin's reading comes from the finalized chain. Our own reclaim
    /// reads `reclaiming` until it is final, then `reclaimed` with the reclaimed amount. A coin still awaiting
    /// its claim after a failed reclaim reads `reclaimFailed`, which beats `unclaimed`: the sender can retry.
    /// Once the claim window has closed, a coin still awaiting its claim makes the payment `unclaimed`.
    func outgoingState(
        context: DenominationBreakdownContext,
        failedReclaims: Set<PublicKey>,
        windowClosed: Bool
    ) -> OutgoingTransferState {
        let states = Array(values)
        guard !states.isEmpty else { return OutgoingTransferState(status: .sending) }

        let claimed = states.filter { if case .claimed = $0.status { true } else { false } }
        let awaiting = states.filter { if case .awaitingClaim = $0.status { true } else { false } }
        let outstanding = states.filter(\.status.isOutstanding)
        let reclaiming = states.filter { $0.status == .reclaiming || $0.status == .reclaimed(finalized: false) }
        let reclaimed = states.filter { $0.status == .reclaimed(finalized: true) }
        let failedAwaiting = awaiting.filter { failedReclaims.contains($0.coin.publicKey) }

        if !reclaiming.isEmpty {
            return OutgoingTransferState(status: .reclaiming)
        }
        if !failedAwaiting.isEmpty {
            return OutgoingTransferState(status: .reclaimFailed)
        }
        if windowClosed, !awaiting.isEmpty {
            return OutgoingTransferState(status: .unclaimed)
        }
        if !reclaimed.isEmpty {
            let amount = reclaimed.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.coin.exponent) }
            return OutgoingTransferState(status: .reclaimed, actualValue: amount)
        }
        if !outstanding.isEmpty {
            guard !awaiting.isEmpty || !claimed.isEmpty else { return OutgoingTransferState(status: .sending) }
            let everyReadingFinal = states.allSatisfy(\.status.isFinalizedReading)
            return OutgoingTransferState(status: everyReadingFinal ? .sentFinalized : .sent)
        }
        guard !claimed.isEmpty else { return OutgoingTransferState(status: .failed) }

        let amount = claimed.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.coin.exponent) }
        return OutgoingTransferState(status: isSettled ? .claimedFinalized : .claimed, actualValue: amount)
    }

    /// Settled once every coin is terminal; a reclaim that is not final keeps the payment open.
    var isSettled: Bool {
        !isEmpty && values.allSatisfy(\.status.isTerminal)
    }
}

private extension CoinageTransferStatus {
    var isOutstanding: Bool {
        switch self {
        case .awaitingClaim,
             .detecting: true
        case .claimed,
             .failed,
             .reclaiming,
             .reclaimed: false
        }
    }

    /// A reading a fork can no longer undo.
    var isFinalizedReading: Bool {
        switch self {
        case .failed: true
        case let .awaitingClaim(finalized),
             let .claimed(finalized),
             let .reclaimed(finalized): finalized
        case .detecting,
             .reclaiming: false
        }
    }
}
