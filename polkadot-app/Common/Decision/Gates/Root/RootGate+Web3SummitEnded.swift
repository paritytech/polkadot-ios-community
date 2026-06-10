import Foundation

extension RootGate {
    struct Web3SummitEnded: DecisionGate {
        private let gate: Web3SummitGate

        init(gate: Web3SummitGate = .makeDefault()) {
            self.gate = gate
        }

        func evaluate() -> RootDestination? {
            guard gate.decide() == .ended else {
                return nil
            }

            return .web3SummitEnded
        }
    }
}
