import Foundation

public typealias ProductId = String

public struct Product: Identifiable {
    public let id: ProductId
    public let name: String

    public init(id: ProductId, name: String) {
        self.id = id
        self.name = name
    }
}

public extension ProductId {
    static func fromUrl(_ url: URL) -> ProductId? {
        ProductHost.fromUrl(url)?.toDotDomain()
    }
}
