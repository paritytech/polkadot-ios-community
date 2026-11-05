import Foundation
import Products
import Testing

@testable import polkadot_app

@Suite("APListRingVrfKeysHandler")
struct APListRingVrfKeysHandlerTests {
    private let builtInKeys = MockBuiltInPersonhoodKeys()
    private let accountAccess = MockAccountAccessPermissionHandler()
    private let entry = RegisteredRingVrfKey(
        handle: RingVrfKeyHandle(productId: "peopl.paseo", index: .index(1)),
        rings: [RingLocation(chainId: Data(repeating: 0x11, count: 32), junctions: [.palletInstance(50)])],
        publicKey: nil
    )

    @Test("Granted access to the owner returns its entries")
    func grantedAccessReturnsEntries() async throws {
        builtInKeys.entries = [entry]

        let entries = try await makeHandler().listRingVrfKeys(owner: "peopl.paseo")

        #expect(entries == [entry])
        #expect(accountAccess.recordedProductIds == ["getcash.paseo"])
        #expect(accountAccess.recordedTargetProductIds == ["peopl.paseo"])
        #expect(builtInKeys.recordedOwners == ["peopl.paseo"])
    }

    @Test("Denied access is rejected without reading the keys")
    func deniedAccessIsRejected() async {
        accountAccess.granted = false

        await #expect(throws: ListRingVrfKeysError.rejected) {
            try await makeHandler().listRingVrfKeys(owner: "peopl.paseo")
        }
        #expect(builtInKeys.recordedOwners.isEmpty)
    }

    @Test("A caller without a product id is rejected")
    func missingCallerIsRejected() async {
        await #expect(throws: ListRingVrfKeysError.rejected) {
            try await makeHandler(callingProductId: nil).listRingVrfKeys(owner: "peopl.paseo")
        }
        #expect(accountAccess.recordedProductIds.isEmpty)
    }

    @Test("Key lookup failures surface as unknown")
    func lookupFailureIsUnknown() async {
        builtInKeys.entriesError = BuiltInPersonhoodKeyError.peopleChainUnavailable

        await #expect(throws: ListRingVrfKeysError.self) {
            try await makeHandler().listRingVrfKeys(owner: "peopl.paseo")
        }
    }
}

private extension APListRingVrfKeysHandlerTests {
    func makeHandler(callingProductId: ProductId? = "getcash.paseo") -> APListRingVrfKeysHandler {
        APListRingVrfKeysHandler(
            callingProductId: callingProductId,
            builtInKeys: builtInKeys,
            accountAccessHandler: accountAccess,
            logger: Logger.shared
        )
    }
}
