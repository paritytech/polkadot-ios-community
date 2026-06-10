import Foundation
import Products

final class ProductSPAOpenService {
    private let moduleNavigator: ModuleNavigating

    init(moduleNavigator: ModuleNavigating) {
        self.moduleNavigator = moduleNavigator
    }
}

extension ProductSPAOpenService: URLHandlingServiceProtocol {
    func handle(url: URL) -> Bool {
        guard let page = ProductPage.fromUrl(url) else {
            return false
        }

        Task { @MainActor in
            moduleNavigator.openProduct(page: page)
        }
        return true
    }
}
