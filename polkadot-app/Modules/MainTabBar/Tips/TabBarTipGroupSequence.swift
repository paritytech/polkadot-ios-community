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

    /// `currentTipUpdates` carries `any Tip`, never `nil` — it announces the next tip that
    /// becomes eligible and stays silent once the last one is invalidated. The per-tip status
    /// streams supply that missing signal, so closing the final tip still resolves to no tip.
    func observeChanges(_ onChange: @escaping @MainActor () -> Void) async {
        let group = group

        await withTaskGroup(of: Void.self) { tasks in
            tasks.addTask { @MainActor in
                for await _ in group.currentTipUpdates {
                    onChange()
                }
            }

            for step in steps {
                tasks.addTask { @MainActor in
                    for await _ in step.tip.shouldDisplayUpdates {
                        onChange()
                    }
                }
            }
        }
    }
}
