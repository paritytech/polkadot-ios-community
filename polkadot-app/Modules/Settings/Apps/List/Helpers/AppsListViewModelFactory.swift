import Foundation
import PolkadotUI
import Products

protocol AppsListViewModelMaking {
    func createItems(from productIds: [ProductId]) -> [AppsListViewLayout.Item]
}

final class AppsListViewModelFactory {
    init() {}
}

extension AppsListViewModelFactory: AppsListViewModelMaking {
    func createItems(from productIds: [ProductId]) -> [AppsListViewLayout.Item] {
        productIds.map { AppsListViewLayout.Item(id: $0, name: $0) }
    }
}
