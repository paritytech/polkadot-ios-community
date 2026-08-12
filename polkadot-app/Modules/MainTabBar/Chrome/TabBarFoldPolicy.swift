import Foundation

enum TabBarFoldState: Equatable {
    case shown
    case folded
}

enum TabBarFoldOverride: Equatable {
    case none
    case folded
    case shown
}

enum TabBarFoldPolicy {
    static func state(
        isTabRoot: Bool,
        stackFolds: Bool,
        override: TabBarFoldOverride
    ) -> TabBarFoldState {
        guard !isTabRoot else {
            return .shown
        }

        switch override {
        case .folded:
            return .folded
        case .shown:
            return .shown
        case .none:
            return stackFolds ? .folded : .shown
        }
    }

    static func contributesClearance(isTabRoot: Bool) -> Bool {
        isTabRoot
    }
}
