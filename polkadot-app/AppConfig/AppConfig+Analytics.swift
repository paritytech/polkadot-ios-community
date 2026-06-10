import Foundation

#if TESTNET_FEATURE
    extension AppConfig {
        enum Analytics {
            static let posthogAPIKey = CIKeys.posthogAPIKey
            static let posthogHost = CIKeys.posthogHost
        }
    }
#endif
