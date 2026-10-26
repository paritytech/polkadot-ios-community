import Foundation

enum DeviceTransferConstants {
    static let statementLifetimeInSeconds: TimeInterval = 15 * 60
    /// A run with no progress for this long ends on both sides.
    static let runIdleTimeout: Duration = .seconds(15 * 60)
}
