import Foundation
import AsyncExtensions

/// Read seam for the release thresholds. The app-side implementation is backed by Remote Config and injected
/// into the package, so the strategy depends only on this protocol.
public protocol CoinagePrivacyConfigProviding: Sendable {
    var privacyConfig: CoinagePrivacyConfig { get }
    /// Emits the current value immediately and again on every change.
    func privacyConfigStream() -> AnyAsyncSequence<CoinagePrivacyConfig>
}
