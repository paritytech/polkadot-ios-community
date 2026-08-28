import Foundation

@testable import polkadot_app

/// Build-flavor deeplink schemes for tests that must hold under any configuration.
enum DeeplinkTestSchemes {
    static let active = AppConfig.DeepLink.scheme
    /// The inactive flavor of the CURRENT brand. Derived from knownSchemes so it stays
    /// correct under any brand; a hardcoded fallback would silently leave a scheme that
    /// knownSchemes does not contain, and DeeplinkSchemeNormalizer would pass it through.
    static let other = AppConfig.DeepLink.knownSchemes.subtracting([active]).first!
}
