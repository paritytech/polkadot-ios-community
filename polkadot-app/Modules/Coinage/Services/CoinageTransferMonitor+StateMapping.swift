import BigInt
import Coinage
import Foundation
import SubstrateSdk

extension CoinageTransferDetection {
    /// `claimingRest` is plain `claiming`: the claimed-so-far amount is deliberately not persisted.
    var incomingState: IncomingTransferState {
        switch self {
        case .detecting:
            IncomingTransferState(status: .detecting)
        case .claiming,
             .claimingRest:
            IncomingTransferState(status: .claiming)
        case let .claimed(amount, _):
            IncomingTransferState(status: .claimed, actualValue: amount)
        case let .claimedPartially(claimed):
            IncomingTransferState(status: .claimed, actualValue: claimed)
        case .notClaimed:
            IncomingTransferState(status: .failed)
        }
    }
}

extension [PublicKey: CoinageTransferState] {
    /// Mirrors Android's `toPaymentStatus`: any coin still to be taken keeps the message at
    /// `sending`/`sent`; once nothing is outstanding, the claimed value is final.
    func outgoingState(context: DenominationBreakdownContext) -> OutgoingTransferState {
        let states = Array(values)
        guard !states.isEmpty else { return OutgoingTransferState(status: .sending) }

        let claimed = states.filter { if case .claimed = $0.status { true } else { false } }
        let awaiting = states.filter { $0.status == .awaitingClaim }
        let outstanding = states.filter { $0.status == .awaitingClaim || $0.status == .detecting }

        if !outstanding.isEmpty {
            return OutgoingTransferState(status: awaiting.isEmpty && claimed.isEmpty ? .sending : .sent)
        }
        guard !claimed.isEmpty else { return OutgoingTransferState(status: .failed) }

        let amount = claimed.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.coin.exponent) }
        return OutgoingTransferState(status: .claimed, actualValue: amount)
    }

    var isSettled: Bool {
        !isEmpty && values.allSatisfy(\.status.isTerminal)
    }
}

extension [PublicKey: RemoteDeviceTransferCoinState] {
    /// Only the chain is visible: a coin on it is `sent`, every coin gone after being seen is `claimed`, and one
    /// never seen keeps the message at `sending`, since it may not be minted yet.
    func outgoingState(context: DenominationBreakdownContext) -> OutgoingTransferState {
        let states = Array(values)
        guard !states.isEmpty else { return OutgoingTransferState(status: .sending) }

        var claimed = Balance(0)
        var seen = false

        for state in states {
            switch state {
            case .notSeen:
                continue
            case .onChain:
                seen = true
            case let .gone(exponent):
                seen = true
                claimed += context.valueInPlanks(for: exponent)
            }
        }

        guard seen else { return OutgoingTransferState(status: .sending) }
        guard isSettled else { return OutgoingTransferState(status: .sent) }

        return OutgoingTransferState(status: .claimed, actualValue: claimed)
    }

    var isSettled: Bool {
        !isEmpty && values.allSatisfy { if case .gone = $0 { true } else { false } }
    }
}
