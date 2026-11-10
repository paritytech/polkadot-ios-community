import UIKit

/// Tells whether the app runs in the background and lets work wait until the user brings it to the foreground.
@MainActor
public protocol ApplicationActivityProviding: Sendable {
    var isInBackground: Bool { get }

    /// Returns at once unless the app is in the background; then waits for the next foreground transition.
    /// Cancelling the caller ends the wait.
    func waitUntilInForeground() async
}

@MainActor
public final class ApplicationActivity {
    private let streamFactory: ApplicationStateStreamFactory

    public nonisolated init(streamFactory: ApplicationStateStreamFactory = ApplicationStateStreamFactory()) {
        self.streamFactory = streamFactory
    }
}

extension ApplicationActivity: ApplicationActivityProviding {
    public var isInBackground: Bool {
        UIApplication.shared.applicationState == .background
    }

    public func waitUntilInForeground() async {
        // Subscribed before the check, so a transition between the two can't be missed.
        let foregroundEvents = streamFactory.stream(for: .willEnterForeground)

        guard isInBackground else { return }

        for await _ in foregroundEvents {
            return
        }
    }
}
