import Foundation

extension RootGate {
    /// Only an installation saved as active reaches the dashboard, so an inactive phone never starts chat or coinage.
    struct Installation: DecisionGate {
        private let statusStore: InstallationStatusStoring

        init(statusStore: InstallationStatusStoring) {
            self.statusStore = statusStore
        }

        func evaluate() -> RootDestination? {
            switch statusStore.status {
            case .active:
                nil
            case .inactive,
                 .unreadable:
                .deviceTransfer
            case nil:
                .installationCheck
            }
        }
    }
}
