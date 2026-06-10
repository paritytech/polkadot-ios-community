import Foundation
import SubstrateSdk
import Testing

@testable import polkadot_app

@Suite("ContextualAlias SCALE Coding Tests")
struct ContextualAliasScaleCodingTests {
    @Test("Roundtrip preserves context and alias")
    func roundtrip() throws {
        let context = Data.random(of: PolkadotHostRemoteMessage.ContextualAlias.contextSize)!
        let alias = Data.random(of: 33)!
        let original = PolkadotHostRemoteMessage.ContextualAlias(context: context, alias: alias)

        let decoded = try encodeThenDecode(original)

        #expect(decoded.context == original.context)
        #expect(decoded.alias == original.alias)
    }

    // MARK: - Helpers

    private func encodeThenDecode(
        _ alias: PolkadotHostRemoteMessage.ContextualAlias
    ) throws -> PolkadotHostRemoteMessage.ContextualAlias {
        let encoder = ScaleEncoder()
        try alias.encode(scaleEncoder: encoder)
        let decoder = try ScaleDecoder(data: encoder.encode())
        return try PolkadotHostRemoteMessage.ContextualAlias(scaleDecoder: decoder)
    }
}
