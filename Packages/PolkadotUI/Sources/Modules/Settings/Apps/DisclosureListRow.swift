import SwiftUI
import DesignSystem

public struct DisclosureListRow<Leading: View>: View {
    private let title: String
    private let leading: Leading
    private let onTap: () -> Void

    public init(
        title: String,
        @ViewBuilder leading: () -> Leading,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.leading = leading()
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                leading

                Text(title)
                    .typography(.titleLarge)
                    .foregroundColor(Color(.fgPrimary))

                Spacer()

                Image(.navigationArrowRight)
                    .renderingMode(.template)
                    .foregroundStyle(Color.fgPrimary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

public extension DisclosureListRow where Leading == EmptyView {
    init(title: String, onTap: @escaping () -> Void) {
        self.init(title: title, leading: { EmptyView() }, onTap: onTap)
    }
}
