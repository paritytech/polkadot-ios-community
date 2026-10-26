import Foundation

/// What an inactive phone shows about the active one, and what the sender shows about a new phone.
/// Built from `utsname` and `ProcessInfo` rather than `UIDevice`, so it can be read off the main actor.
struct DeviceInfo: Equatable {
    let model: String
    let operatingSystem: String

    static func current() -> DeviceInfo {
        let identifier = machineIdentifier()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let systemName = identifier.hasPrefix("iPad") ? "iPadOS" : "iOS"
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""

        return DeviceInfo(
            model: DeviceModelNames.name(for: identifier) ?? genericModel(for: identifier),
            operatingSystem: "\(systemName) \(version.majorVersion).\(version.minorVersion)\(patch)"
        )
    }
}

private extension DeviceInfo {
    static func machineIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }

        var systemInfo = utsname()
        uname(&systemInfo)

        let machine = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            Data(buffer.prefix { $0 != 0 })
        }

        return String(bytes: machine, encoding: .utf8) ?? ""
    }

    static func genericModel(for identifier: String) -> String {
        identifier.hasPrefix("iPad") ? "iPad" : "iPhone"
    }
}

/// Marketing names for the iPhones that run the minimum supported iOS. iOS has no public API for them, so the
/// table needs a new row each September; unknown identifiers fall back to "iPhone" or "iPad".
enum DeviceModelNames {
    static func name(for identifier: String) -> String? {
        names[identifier]
    }

    private static let names: [String: String] = [
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air"
    ]
}
