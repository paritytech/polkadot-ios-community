import Foundation

/// The last status an installation service settled on, read at launch before the record topic is reachable.
enum SavedInstallationStatus: Codable, Equatable {
    case active
    case inactive(ActiveInstallation)
    case unreadable
}

protocol InstallationStatusStoring: Sendable {
    var status: SavedInstallationStatus? { get }
    /// Set the first time this installation is active, so a later `inactive` means it was replaced.
    var hasBeenActive: Bool { get }

    func save(_ status: InstallationStatus)
}

/// `@unchecked`: `UserDefaults` is thread-safe. Kept in the app group so the notification extension can read it.
final class InstallationStatusStore: @unchecked Sendable {
    private static let statusKey = SettingsKey.installationStatus.rawValue
    private static let hasBeenActiveKey = SettingsKey.installationHasBeenActive.rawValue

    private let userDefaults: UserDefaults
    private let logger: LoggerProtocol

    init(userDefaults: UserDefaults = SharedContainerGroup.userDefaults, logger: LoggerProtocol) {
        self.userDefaults = userDefaults
        self.logger = logger
    }
}

extension InstallationStatusStore: InstallationStatusStoring {
    var status: SavedInstallationStatus? {
        guard let data = userDefaults.data(forKey: Self.statusKey) else { return nil }

        do {
            return try JSONDecoder().decode(SavedInstallationStatus.self, from: data)
        } catch {
            logger.error("Saved installation status can't be read: \(error)")
            return nil
        }
    }

    var hasBeenActive: Bool {
        userDefaults.bool(forKey: Self.hasBeenActiveKey)
    }

    func save(_ status: InstallationStatus) {
        guard let saved = SavedInstallationStatus(status) else { return }

        do {
            try userDefaults.set(JSONEncoder().encode(saved), forKey: Self.statusKey)
        } catch {
            logger.error("Installation status can't be saved: \(error)")
            return
        }

        if saved == .active {
            userDefaults.set(true, forKey: Self.hasBeenActiveKey)
        }
    }
}

private extension SavedInstallationStatus {
    /// `unknown` only means the store wasn't read yet, so it never replaces what was saved.
    init?(_ status: InstallationStatus) {
        switch status {
        case .unknown:
            return nil
        case .active:
            self = .active
        case let .inactive(installation):
            self = .inactive(installation)
        case .unreadable:
            self = .unreadable
        }
    }
}
