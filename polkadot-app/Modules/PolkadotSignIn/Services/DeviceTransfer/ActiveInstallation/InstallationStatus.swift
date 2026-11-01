import Foundation

enum InstallationStatus: Equatable {
    /// The store wasn't read yet or was unreachable; callers keep the last known status.
    case unknown
    case active
    case inactive(ActiveInstallation)
    /// Records exist but none could be read: another key or an unknown version.
    case unreadable
}
