import DesignSystem
import SwiftUI

public struct PaymentHistoryViewLayout: View {
    @State private var viewModel: PaymentHistoryViewModel

    public init(viewModel: PaymentHistoryViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DSSpacings.small) {
                if viewModel.items.isEmpty {
                    Text(verbatim: "No payment history yet")
                        .typography(.bodyMedium)
                        .foregroundStyle(Color.fgSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, DSSpacings.large)
                } else {
                    ForEach(viewModel.items) { item in
                        row(item: item)
                    }
                }
            }
        }
        .contentMargins(.horizontal, DSSpacings.mediumIncreased)
        .contentMargins(.top, DSSpacings.small)
        .background(Color.bgSurfaceMain)
    }

    @ViewBuilder
    private func row(item: PaymentHistoryViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: DSSpacings.extraSmall) {
            HStack {
                Text(item.title)
                    .typography(.titleMedium)
                    .foregroundStyle(Color.fgPrimary)
                    .lineLimit(1)
                Spacer()
                Text(item.statusText)
                    .typography(.labelMedium.emphasized)
                    .foregroundStyle(Color.fgSecondary)
            }
            HStack {
                Text(verbatim: "Amount:")
                    .typography(.bodyMedium.emphasized)
                    .foregroundStyle(Color.fgPrimary)

                Text(item.amount)
                    .typography(.bodyMedium.emphasized)
                    .foregroundStyle(Color.fgPrimary)
            }
            Text(item.date)
                .typography(.bodySmall)
                .foregroundStyle(Color.fgSecondary)
            if let reason = item.failureReason {
                Text(reason)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.fgError)
                    .lineLimit(2)
            }
        }
        .padding(DSSpacings.mediumIncreased)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.bgSurfaceContainer,
            in: RoundedRectangle(cornerRadius: DSRadii.mediumIncreased)
        )
    }
}

#Preview {
    PaymentHistoryViewLayout(viewModel: PaymentHistoryViewModel())
}
