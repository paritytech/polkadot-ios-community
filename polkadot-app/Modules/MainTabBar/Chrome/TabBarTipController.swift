import PolkadotUI
import TipKit
import UIKit
import UIKitExt

@MainActor
final class TabBarTipController {
    private let barView: DSTabBarView
    private let itemIndex: (TabBarSlot) -> Int?
    private let sequence: any TabBarTipSequenceProtocol

    private weak var host: UIViewController?
    private var observation: Task<Void, Never>?

    /// Which tip is currently on screen. A presented `TipUIPopoverViewController` cannot be
    /// asked which tip it holds, and "on screen" differs from `sequence.currentStep` ("should
    /// be on screen") during the window before an anchor resolves.
    private var presentedTip: AnyTip?

    init(
        host: UIViewController,
        barView: DSTabBarView,
        sequence: any TabBarTipSequenceProtocol,
        itemIndex: @escaping (TabBarSlot) -> Int?
    ) {
        self.host = host
        self.barView = barView
        self.sequence = sequence
        self.itemIndex = itemIndex
    }

    func start() {
        guard observation == nil else {
            return
        }

        let sequence = sequence

        observation = Task { @MainActor in
            await sequence.observeChanges { [weak self] in
                self?.presentCurrent()
            }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil

        dismiss()
    }

    func setBarShown(_ isShown: Bool) {
        TabBarTips.isBarShownAtRoot = isShown
    }

    func retireForUserInteraction() {
        guard let presentedTip else {
            return
        }

        presentedTip.invalidate(reason: .actionPerformed)
    }

    func dismissForPanel() {
        dismiss()
    }

    /// Item views are recreated by `rebuildItems()`, and the slot map is empty until the first
    /// `setItems`, so re-resolve the anchor and present again while a tip is still eligible.
    /// Clearing `presentedTip` is enough — the dismissal is left to `present(_:)` so only one
    /// transition runs.
    func refreshAnchor() {
        presentedTip = nil
        presentCurrent()
    }
}

private extension TabBarTipController {
    func present(_ step: TabBarTipStep) {
        guard let host, host.presentedViewController is TipUIPopoverViewController else {
            show(step)
            return
        }

        presentedTip = nil
        host.dismiss(animated: true) { [weak self] in
            self?.show(step)
        }
    }

    func show(_ step: TabBarTipStep) {
        guard let host,
              host.presentedViewController == nil,
              let index = itemIndex(step.slot),
              let anchor = barView.itemAnchor(at: index)
        else {
            return
        }

        let controller = TipUIPopoverViewController(step.tip, sourceItem: anchor)
        controller.popoverPresentationController?.permittedArrowDirections = .down
        controller.popoverPresentationController?.passthroughViews = [barView]

        host.present(controller, animated: true)
        presentedTip = step.tip
    }

    func dismiss() {
        presentedTip = nil

        guard let host, host.presentedViewController is TipUIPopoverViewController else {
            return
        }

        host.dismiss(animated: true)
    }

    /// The single decision point. Idempotent: re-presenting the step already on screen is a
    /// no-op, so a re-emission cannot flicker a live popover.
    func presentCurrent() {
        guard let step = sequence.currentStep else {
            dismiss()
            return
        }

        guard presentedTip?.id != step.tip.id else {
            return
        }

        present(step)
    }
}

extension TipUIPopoverViewController: @retroactive TransientPresentationSkipping {}
