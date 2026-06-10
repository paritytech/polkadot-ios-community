import SwiftUI
import DesignSystem

public struct AppsListViewLayout: View {
    public struct Item: Identifiable, Hashable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    @State public var viewModel = AppsListViewModel()

    public init() {}

    public var body: some View {
        Group {
            if viewModel.items.isEmpty {
                emptyState
            } else {
                appsList
            }
        }
    }
}

// MARK: - Private Views

private extension AppsListViewLayout {
    var emptyState: some View {
        VStack {
            Spacer()
            Text(String(localized: .appsListEmpty))
                .typography(.bodyMedium)
                .foregroundColor(Color(.fgSecondary))
            Spacer()
        }
    }

    var appsList: some View {
        List {
            ForEach(viewModel.items) { item in
                appRow(for: item)
            }
        }
        .listRowSpacing(16)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    func appRow(for item: Item) -> some View {
        DisclosureListRow(
            title: item.name,
            leading: { AppIconPlaceholder(size: 32, cornerRadius: 8) },
            onTap: { viewModel.onSelect?(item) }
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
