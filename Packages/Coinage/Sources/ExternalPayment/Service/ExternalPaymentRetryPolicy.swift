import Foundation

/// Bounds the transient-failure retry loop around the payment state machine.
///
/// Bounded (unlike Android's WorkManager retries) because the user is waiting inside the product;
/// after `window` from `createdAt` the payment is persisted as failed with the last error.
struct ExternalPaymentRetryPolicy: Sendable {
    let window: TimeInterval
    let backoff: TimeInterval
    let maxBackoff: TimeInterval
    let sleep: @Sendable (TimeInterval) async throws -> Void

    static let production = ExternalPaymentRetryPolicy(
        window: CoinageConstants.externalPaymentRetryWindow,
        backoff: CoinageConstants.externalPaymentRetryBackoff,
        maxBackoff: CoinageConstants.externalPaymentMaxRetryBackoff,
        sleep: { try await Task.sleep(for: .seconds($0)) }
    )

    /// Linear backoff, capped: 30s, 60s, 90s … up to `maxBackoff`.
    func delay(forAttempt attempt: Int) -> TimeInterval {
        min(TimeInterval(attempt) * backoff, maxBackoff)
    }

    func hasWindowElapsed(since createdAt: Date, now: Date = Date()) -> Bool {
        now >= createdAt.addingTimeInterval(window)
    }
}
