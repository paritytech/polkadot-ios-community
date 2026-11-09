import Foundation

/// The current time for code that can't await, such as statement expiry built inside the session engine.
public protocol SynchronousTimeProviding: Sendable {
    var now: Date { get }
}

public struct SystemTimeProvider: SynchronousTimeProviding {
    public init() {}

    public var now: Date {
        Date()
    }
}
