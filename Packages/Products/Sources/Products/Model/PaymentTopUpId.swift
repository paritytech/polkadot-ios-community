import Foundation
import SubstrateSdk

/// The product's own name for a top-up, and the only thing that identifies it — 32 opaque bytes
/// (`[u8; 32]`), supplied by the product. Never parsed or shortened by the host; only compared, and
/// rendered as hex where a string is needed. Mirrors Android's `PaymentTopUpId`.
public struct PaymentTopUpId: Hashable, Sendable {
    public static let sizeBytes = 32

    public let bytes: Data

    private init(validated bytes: Data) {
        self.bytes = bytes
    }

    public func asHex() -> String {
        bytes.toHex()
    }

    public static func fromBytes(_ bytes: Data) throws -> PaymentTopUpId {
        guard bytes.count == sizeBytes else {
            throw PaymentTopUpIdError.invalidLength(bytes.count)
        }
        return PaymentTopUpId(validated: bytes)
    }

    public static func fromHex(_ hex: String) throws -> PaymentTopUpId {
        try fromBytes(Data(hexString: hex))
    }
}

public enum PaymentTopUpIdError: Error, Equatable {
    case invalidLength(Int)
}

extension PaymentTopUpId: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try PaymentTopUpId.fromHex(container.decode(String.self))
    }
}
