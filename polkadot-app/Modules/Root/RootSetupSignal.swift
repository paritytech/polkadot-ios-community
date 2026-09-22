import Foundation

/// What `RootSetupObserver` reports to Root. It watches the network path and chain-sync completion;
/// it never decides the outcome of setup, it only says what happened.
enum RootSetupSignal {
    case connectivityRecovered
    case connectivityLost
    case chainsIncomplete
}
