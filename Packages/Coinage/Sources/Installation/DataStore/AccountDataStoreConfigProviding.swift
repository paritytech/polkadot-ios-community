import Foundation

/// The `AccountDataStore` contract address (20-byte EVM address) from remote config; `nil` until it
/// is delivered.
public protocol AccountDataStoreConfigProviding: Sendable {
    func contractAddress() async -> Data?
}
