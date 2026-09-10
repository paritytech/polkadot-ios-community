import TipKit
import UIKit

@available(iOS 18, *)
@MainActor
final class TabBarTipGroupSequence: TabBarTipSequenceProtocol {
    private let steps: [TabBarTipStep]
    private let group: TipGroup

    var currentStep: TabBarTipStep? {
        guard let id = group.currentTip?.id else {
            return nil
        }

        return steps.first { $0.tip.id == id }
    }

    init(steps: [TabBarTipStep]) {
        self.steps = steps
        group = TipGroup(.ordered) { steps.map(\.tip) }
    }

    func observeChanges(_ onChange: @escaping @MainActor () -> Void) async {
        for await _ in group.currentTipUpdates {
            onChange()
        }
    }
}
