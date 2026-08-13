import Foundation

@testable import polkadot_app

/// Build-flavor deeplink schemes for tests that must hold under any configuration.
enum DeeplinkTestSchemes {
    static let active = AppConfig.DeepLink.scheme
    static let other = active == "polkadotapp" ? "polkadotappdev" : "polkadotapp"
}
