import Foundation
import Keystore_iOS

#if TESTNET_FEATURE
    private let defaultTrUAPIRuntimeEnabled = true
#else
    private let defaultTrUAPIRuntimeEnabled = false
#endif

extension SettingsManagerProtocol {
    /// Builds that ship the Debug Settings toggle default to TrUAPI, so only a deliberate opt-out
    /// selects native. Release ships no toggle and stays on native until the rollout is signed off.
    /// The default cannot live in `value(for:)` — that helper is shared by every boolean setting.
    var isTrUAPIRuntimeEnabled: Bool {
        bool(for: SettingsKey.truApiRuntimeEnabled.rawValue) ?? defaultTrUAPIRuntimeEnabled
    }
}
