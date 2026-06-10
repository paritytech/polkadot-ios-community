import Foundation

// Must be in sync with Coinage pallet
enum RecyclerCollectionIdentifier {
    /// `RECYCLER_COLLECTION_PREFIX` from the Coinage pallet: `b"coinage/recycler"` (16 bytes)
    private static let prefix = Data("coinage/recycler".utf8)

    /// Builds the 32-byte collection identifier for a recycler of the given coin value (exponent).
    ///
    /// Layout: `prefix[0..16] + coinValue[16] + zeros[17..31]`
    static func identifier(for coinValue: Int16) -> Data {
        let padding = Data(repeating: 0, count: 32)
        var data = Data(prefix + padding).prefix(16)
        data.append(contentsOf: [UInt8(clamping: coinValue)])

        return Data(data + padding).prefix(32)
    }
}
