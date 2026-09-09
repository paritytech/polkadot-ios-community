import SwiftUI
import UIKitExt

public struct ChainConnectionStatusBarView: View, Hashable {
    // Height of the bar the container reserves via `additionalSafeAreaInsets.top`.
    public static let preferredHeight: CGFloat = 20

    private static let bottomSpacing: CGFloat = 8

    private static var bottomPadding: CGFloat {
        guard #available(iOS 26.0, *) else { return 0 }

        let topInset = UIWindow.keyWindow?.safeAreaInsets.top ?? 0
        let surplus = max(0, topInset - preferredHeight)

        return surplus > bottomSpacing ? bottomSpacing : 0
    }

    private static var horizontalPadding: CGFloat {
        guard #available(iOS 26.0, *) else { return 6 }

        let topInset = UIWindow.keyWindow?.safeAreaInsets.top ?? 0
        return topInset > 0 ? 16 : 6
    }

    public let models: [ChainConnectionStatusViewModel]

    public init(models: [ChainConnectionStatusViewModel]) {
        self.models = models
    }

    public var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(models) { viewModel in
                ChainStatusRingView(viewModel: viewModel)
            }
        }
        .safeAreaPadding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.preferredHeight)
        // Grows the view's intrinsic height upward into the unused status-bar
        // headroom. Deliberately not part of `preferredHeight`.
        .padding(.bottom, Self.bottomPadding)
    }
}
