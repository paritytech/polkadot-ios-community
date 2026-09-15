import Foundation

/// Locates one own coin or voucher key: the installation subtree it was allocated in, and its item
/// there. Persisted as the identifier `"{installationHex}/{item}"`.
public struct CoinageKeyIndex: Hashable, Sendable {
    public static let identifierSeparator: Character = "/"

    public let installation: CoinageInstallationId
    public let item: UInt32

    public init(installation: CoinageInstallationId, item: UInt32) {
        self.installation = installation
        self.item = item
    }

    public init?(identifier: String) {
        let parts = identifier.split(separator: Self.identifierSeparator, maxSplits: 1)
        guard parts.count == 2,
              let installation = try? CoinageInstallationId(hex: String(parts[0])),
              let item = UInt32(parts[1])
        else { return nil }
        self.init(installation: installation, item: item)
    }

    public var identifier: String {
        "\(installation.hex)\(Self.identifierSeparator)\(item)"
    }

    /// The next item in the same installation.
    public func next() -> CoinageKeyIndex {
        CoinageKeyIndex(installation: installation, item: item + 1)
    }
}

extension CoinageKeyIndex: Comparable {
    public static func < (lhs: CoinageKeyIndex, rhs: CoinageKeyIndex) -> Bool {
        if lhs.installation != rhs.installation {
            return lhs.installation < rhs.installation
        }
        return lhs.item < rhs.item
    }
}

extension CoinageKeyIndex: CustomStringConvertible {
    public var description: String { identifier }
}
