import Foundation

enum SharedContainerGroup {
    static var name: String {
        #if F_DEV
            return "group.io.parity.polkadotapp.develop"
        #else
            return "group.io.parity.polkadotapp"
        #endif
    }

    static var containerURL: URL {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: name) else {
            fatalError(
                "App Group container '\(name)' missing — entitlement not applied"
            )
        }
        return url
    }

    static var userDefaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Failed to create UserDefaults for suite: \(name)")
        }
        return defaults
    }
}
