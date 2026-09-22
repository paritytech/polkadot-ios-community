import Foundation

/// Why setup gave up. Determines the failure screen's copy.
enum RootSetupFailureKind: Equatable {
    /// The network path was unsatisfied when setup gave up.
    case connectivity
    case unknown
}
