import Foundation
import SubstrateSdk

/// Encoded as the 2-element JSON tuple `[productId, derivationIndex]` to match the wire format used by product scripts.
public struct ProductAccountId: Hashable, Codable {
    public let productId: ProductId
    public let derivationIndex: UInt32

    public var derivationPath: String { "/product/\(productId)/\(derivationIndex)" }

    public init(productId: ProductId, derivationIndex: UInt32) {
        self.productId = productId
        self.derivationIndex = derivationIndex
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        productId = try container.decode(ProductId.self)
        derivationIndex = try container.decode(UInt32.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(productId)
        try container.encode(derivationIndex)
    }
}

public struct ProductsAlias {
    public let context: Data
    public let alias: Data

    public init(context: Data, alias: Data) {
        self.context = context
        self.alias = alias
    }
}

extension ProductAccountId: ScaleCodable {
    public init(scaleDecoder: any ScaleDecoding) throws {
        productId = try String(scaleDecoder: scaleDecoder)
        derivationIndex = try UInt32(scaleDecoder: scaleDecoder)
    }

    public func encode(scaleEncoder: any ScaleEncoding) throws {
        try productId.encode(scaleEncoder: scaleEncoder)
        try derivationIndex.encode(scaleEncoder: scaleEncoder)
    }
}
