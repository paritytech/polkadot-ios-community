import Coinage
import Foundation
import Products
import SubstrateSdk
import UIKit
import UIKitExt

enum TopUpAcknowledgementError: Error {
    /// The chain asset the sheet formats against is not registered.
    case screenUnavailable
    /// The topmost controller stayed mid-transition for the whole retry budget.
    case anchorBusy
    /// UIKit refused the presentation (the anchor already presents something).
    case presentationRefused
}

/// Surfaces a top-up's unhappy ending to the user, raised from the durable operation on settle (the
/// `paymentTopUp` call has long since returned). Only the two unhappy terminal outcomes reach here.
///
/// The prompt is app-global: it can settle while any product context — or none — is on screen, so it
/// presents on the key window's topmost controller rather than a per-product router. Prompts are
/// queued so two payments settling together show one sheet after the other, a prompt raised before
/// there is a window waits for the app to become active, and `acknowledge` returns only once the
/// sheet was dismissed — the caller records the user as told on that basis.
final class TopUpAcknowledgementPresenter: IncomingPaymentAcknowledging, @unchecked Sendable {
    private static let anchorRetryDelay: Duration = .milliseconds(250)
    private static let anchorRetryBudget = 20

    private let logger: LoggerProtocol
    private let notificationCenter: NotificationCenter

    @MainActor private var queueTail: Task<Void, Never>?

    init(logger: LoggerProtocol = Logger.shared, notificationCenter: NotificationCenter = .default) {
        self.logger = logger
        self.notificationCenter = notificationCenter
    }

    func acknowledge(
        productId: String,
        paymentId _: IncomingPaymentId,
        requestedAmount: Balance,
        outcome: IncomingPaymentTerminalOutcome
    ) async throws {
        switch outcome {
        case let .claimedPartially(actualClaimed):
            try await enqueue {
                try await self.presentUntilDismissed(
                    TopUpAcknowledgementViewFactory.createMismatchView(
                        productId: productId,
                        claimedAmount: actualClaimed,
                        requestedAmount: requestedAmount
                    )
                )
            }
        case .notClaimed:
            try await enqueue {
                try await self.presentUntilDismissed(
                    TopUpAcknowledgementViewFactory.createErrorView(productId: productId)
                )
            }
        case .claimed:
            break
        }
    }
}

// MARK: - Serialization

private extension TopUpAcknowledgementPresenter {
    /// Runs `work` after every prompt queued before it has finished, so sheets never race for the
    /// same anchor. Cancelling the caller cancels its own prompt without disturbing the queue.
    @MainActor
    func enqueue(_ work: @escaping @MainActor () async throws -> Void) async throws {
        let previous = queueTail
        let prompt = Task { @MainActor in
            await previous?.value
            try await work()
        }
        queueTail = Task { _ = await prompt.result }

        try await withTaskCancellationHandler {
            try await prompt.value
        } onCancel: {
            prompt.cancel()
        }
    }
}

// MARK: - Presentation

private extension TopUpAcknowledgementPresenter {
    @MainActor
    func presentUntilDismissed(_ view: (any ControllerBackedProtocol)?) async throws {
        guard let view else {
            logger.warning("Top-up acknowledgement could not build its screen")
            throw TopUpAcknowledgementError.screenUnavailable
        }

        let anchor = try await awaitAnchor()
        try await present(view.controller, on: anchor)
    }

    /// The key window's topmost controller once it is not mid-transition. With no key window (a
    /// background or VoIP launch) this waits for the app to become active; a transitioning anchor is
    /// re-checked at ``anchorRetryDelay`` up to ``anchorRetryBudget`` times.
    @MainActor
    func awaitAnchor() async throws -> UIViewController {
        var busyChecks = 0
        while true {
            try Task.checkCancellation()

            guard let window = UIWindow.keyWindow else {
                logger.warning("Top-up acknowledgement has no window yet; waiting for the app to become active")
                await awaitDidBecomeActive()
                continue
            }

            if let anchor = window.topmostViewController, anchor.transitionCoordinator == nil {
                return anchor
            }

            busyChecks += 1
            guard busyChecks < Self.anchorRetryBudget else {
                throw TopUpAcknowledgementError.anchorBusy
            }
            try await Task.sleep(for: Self.anchorRetryDelay)
        }
    }

    @MainActor
    func awaitDidBecomeActive() async {
        for await _ in notificationCenter.notifications(named: UIApplication.didBecomeActiveNotification) {
            return
        }
    }

    /// Presents `controller` and suspends until it has left the screen. UIKit refuses a presentation
    /// silently when the anchor is already presenting, so that is checked right after the call rather
    /// than trusted — an unresumed continuation would block every later prompt.
    @MainActor
    func present(_ controller: UIViewController, on anchor: UIViewController) async throws {
        guard let dismissible = controller as? TopUpAcknowledgementDismissObserving else {
            throw TopUpAcknowledgementError.screenUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dismissible.onDidDisappear = { continuation.resume() }
            anchor.present(controller, animated: true)

            guard anchor.presentedViewController === controller else {
                dismissible.onDidDisappear = nil
                continuation.resume(throwing: TopUpAcknowledgementError.presentationRefused)
                return
            }
        }
    }
}

/// A sheet that reports when it has left the screen, so the presenter can await its dismissal.
@MainActor
protocol TopUpAcknowledgementDismissObserving: AnyObject {
    var onDidDisappear: (() -> Void)? { get set }
}
