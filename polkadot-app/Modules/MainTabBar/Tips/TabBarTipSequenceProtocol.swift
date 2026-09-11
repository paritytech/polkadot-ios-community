import TipKit

/// Answers which tip should be on screen and signals when that answer may have changed.
/// Two implementations: TipGroup on iOS 18+, ordered availability below it.
@MainActor
protocol TabBarTipSequenceProtocol: AnyObject {
    var currentStep: TabBarTipStep? { get }

    /// Runs until cancelled, invoking `onChange` whenever `currentStep` may have changed.
    func observeChanges(_ onChange: @escaping @MainActor () -> Void) async
}

enum TabBarTipSequenceFactory {
    @MainActor
    static func make(steps: [TabBarTipStep]) -> any TabBarTipSequenceProtocol {
        if #available(iOS 18, *) {
            return TabBarTipGroupSequence(steps: steps)
        }

        return TabBarTipOrderedSequence(steps: steps)
    }
}
