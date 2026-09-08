import Foundation
import KeyDerivation
import Testing

/// Guards the new-chain launch reset. The entropy-id pointer was renamed with a `.v2` suffix so a
/// returning user's pre-relaunch UserDefaults value is never read again: `getEntropyId()` returns nil,
/// which makes `RootEntropyManager.hasRootEntropy()` short-circuit to false and route to onboarding.
@Suite("Root entropy id store new-chain rename")
struct RootEntropyIdStoreTests {
    /// The pointer key value shipped before the new-chain launch reset.
    private let preRelaunchEntropyIdKey = "io.polkadot.app.entropy.id"

    @Test("a pre-relaunch entropy-id pointer is treated as absent")
    func ignoresPreRelaunchPointer() throws {
        let suiteName = "test.release-key-rename.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Simulate a returning TestFlight user whose device still holds the old pointer.
        defaults.set("pre-relaunch-entropy-uuid", forKey: preRelaunchEntropyIdKey)

        let store = RootEntropyIdStore(userDefaults: defaults)

        // The store now reads the renamed key, so the orphaned old value is invisible.
        #expect(store.getEntropyId() == nil)
    }

    @Test("a fresh user still saves and reads the entropy-id pointer")
    func freshPointerRoundTrips() throws {
        let suiteName = "test.release-key-rename.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RootEntropyIdStore(userDefaults: defaults)
        store.saveEntropyId("fresh-entropy-uuid")

        #expect(store.getEntropyId() == "fresh-entropy-uuid")
        // Writing the new pointer must not resurrect a read of the pre-relaunch key.
        #expect(defaults.string(forKey: preRelaunchEntropyIdKey) == nil)
    }
}
