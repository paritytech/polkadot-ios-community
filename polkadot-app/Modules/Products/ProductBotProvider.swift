import AsyncExtensions
import Foundation
import Operation_iOS
import Products
import StructuredConcurrency

protocol ProductBotProviding {
    func observeBots() -> AnyAsyncSequence<[ProductBot]>
}

final class ProductBotProvider: ProductBotProviding {
    private let productProvider: StreamableProvider<Product>
    private let botFactory: ProductBotFactory

    init(
        productProvider: StreamableProvider<Product>,
        botFactory: ProductBotFactory
    ) {
        self.productProvider = productProvider
        self.botFactory = botFactory
    }

    func observeBots() -> AnyAsyncSequence<[ProductBot]> {
        productProvider.asyncStream()
            .scan([String: Product]()) { dict, changes in
                changes.mergeToDict(dict)
            }
            .map { [botFactory] productDict in
                productDict.values.compactMap { product in
                    botFactory.create(product: product)
                }
            }
            .eraseToAnyAsyncSequence()
    }
}
