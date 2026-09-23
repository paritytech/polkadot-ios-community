import UIKit

/// Collects the prompts `ProductsRouter` presents while the scope is bound to
/// the current task, so a request that is withdrawn can take its prompts down.
/// Once withdrawn, the scope refuses further prompts and the flow delivers its
/// own rejection, as it does when no view is anchored.
@MainActor
public final class PromptPresentationScope {
    /// The scope bound to the current task, if any.
    public nonisolated static var current: PromptPresentationScope? {
        BoundScope.value
    }

    private var controllers: [WeakController] = []
    public private(set) var isWithdrawn = false

    public nonisolated init() {}

    /// Registers a prompt about to be presented; `false` means the scope is
    /// withdrawn and the prompt must not be shown.
    public func admit(_ controller: UIViewController) -> Bool {
        guard !isWithdrawn else {
            return false
        }

        controllers.append(WeakController(controller))
        return true
    }

    /// Dismisses every prompt still on screen and refuses later ones.
    public func withdraw() {
        isWithdrawn = true

        for controller in controllers.compactMap(\.controller) where !controller.isBeingDismissed {
            controller.presentingViewController?.dismiss(animated: true)
        }

        controllers.removeAll()
    }

    /// Runs `operation` with this scope bound.
    public nonisolated func bind<T>(_ operation: () async -> T) async -> T {
        await BoundScope.$value.withValue(self) {
            await operation()
        }
    }

    /// Runs `operation` with this scope bound; cancelling the calling task
    /// withdraws the scope.
    @discardableResult
    public nonisolated func run<T>(_ operation: () async -> T) async -> T {
        await withTaskCancellationHandler {
            await bind(operation)
        } onCancel: {
            Task { @MainActor in self.withdraw() }
        }
    }
}

private enum BoundScope {
    @TaskLocal static var value: PromptPresentationScope?
}

private struct WeakController {
    weak var controller: UIViewController?

    init(_ controller: UIViewController) {
        self.controller = controller
    }
}
