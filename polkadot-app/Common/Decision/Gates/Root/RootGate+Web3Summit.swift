import Foundation

extension RootGate {
    struct Web3Summit: DecisionGate {
        private let gate: Web3SummitGate

        init(gate: Web3SummitGate = .makeDefault()) {
            self.gate = gate
        }

        func evaluate() -> RootDestination? {
            switch gate.decide() {
            case .main: nil
            case .ended: .web3SummitEnded
            case .spa: .web3SummitSpa
            }
        }
    }
}
