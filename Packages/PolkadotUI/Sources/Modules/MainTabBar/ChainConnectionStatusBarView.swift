import SwiftUI

public struct ChainConnectionStatusBarView: View, Hashable {
    public static let preferredHeight: CGFloat = 20

    public let rows: [ChainConnectionStatusViewModel]

    public init(rows: [ChainConnectionStatusViewModel]) {
        self.rows = rows
    }

    public var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(rows) { row in
                ChainStatusRingView(row: row)
            }
        }
        .safeAreaPadding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.preferredHeight)
    }
}
