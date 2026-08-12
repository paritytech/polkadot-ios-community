import UIKit

@MainActor
enum TabBarHiddenPolicy {
    static func isBarHidden(in stack: [UIViewController], showing target: UIViewController) -> Bool {
        let targetIndex = stack.firstIndex(of: target) ?? stack.index(before: stack.endIndex)

        guard stack.indices.contains(targetIndex) else {
            return false
        }

        return stack[...targetIndex].dropFirst().contains { $0.hidesBottomBarWhenPushed }
    }

    static func isTabRoot(in stack: [UIViewController], showing target: UIViewController) -> Bool {
        target === stack.first
    }

    static func stackAfterCancelledPop(
        stack: [UIViewController],
        staying: UIViewController
    ) -> [UIViewController] {
        stack.contains(staying) ? stack : stack + [staying]
    }
}
