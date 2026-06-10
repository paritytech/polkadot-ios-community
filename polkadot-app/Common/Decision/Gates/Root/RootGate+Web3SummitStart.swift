import Foundation

extension RootGate {
    struct Web3SummitStart: DecisionGate {
        private let modeProvider: Web3SummitStartGateProviding

        init(
            modeProvider: Web3SummitStartGateProviding = Web3SummitStartGateProvider(
                remoteConfig: FirebaseFacade.shared
            )
        ) {
            self.modeProvider = modeProvider
        }

        func evaluate() -> RootDestination? {
            guard modeProvider.current() == .notStarted else {
                return nil
            }

            return .web3SummitNotStarted
        }
    }
}
