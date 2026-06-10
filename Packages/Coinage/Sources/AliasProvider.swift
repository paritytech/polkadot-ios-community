import Foundation
import KeyDerivation
import SubstrateSdk

/// Abstracts alias derivation for coinage operations.
public protocol AliasProviding: AnyObject {
    /// Derives an alias for the given context.
    /// - Parameter context: The context data (e.g., unload token context).
    /// - Returns: A 32-byte alias.
    func deriveAlias(for context: Data) throws -> Data
}

/// Alias provider for ring members that delegates to BandersnatchKeyManaging.
public final class RingMemberAliasProvider: AliasProviding {
    private let keyManager: any BandersnatchKeyManaging

    public init(keyManager: any BandersnatchKeyManaging) {
        self.keyManager = keyManager
    }

    public func deriveAlias(for context: Data) throws -> Data {
        try keyManager.deriveAlias(for: context)
    }
}
