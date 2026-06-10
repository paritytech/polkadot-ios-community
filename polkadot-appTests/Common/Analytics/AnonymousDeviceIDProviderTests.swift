import Testing
import Foundation
import KeyDerivation
import Keystore_iOS
@testable import polkadot_app

@Suite("AnonymousDeviceIDProvider")
struct AnonymousDeviceIDProviderTests {
    let generatedUUID: UUID
    let keychain: InMemoryKeychain
    let provider: AnonymousDeviceIDProvider

    init() {
        let generatedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        self.generatedUUID = generatedUUID
        keychain = InMemoryKeychain()
        provider = AnonymousDeviceIDProvider(
            keychain: keychain,
            generateUUID: { generatedUUID }
        )
    }

    @Test("Returns existing anonymous device ID")
    func returnsExistingID() throws {
        let existingID = "existing-id"
        try keychain.saveKey(Data(existingID.utf8), with: KeystoreTag.anonymousDeviceIDTag)

        let id = provider.getOrCreate()

        #expect(id == existingID)
    }

    @Test("Creates and stores anonymous device ID when missing")
    func createsAndStoresNewID() throws {
        let id = provider.getOrCreate()

        let storedData = try keychain.fetchKey(for: KeystoreTag.anonymousDeviceIDTag)
        let storedID = try #require(String(data: storedData, encoding: .utf8))
        #expect(id == generatedUUID.uuidString)
        #expect(storedID == generatedUUID.uuidString)
    }

    @Test("Returns stored anonymous device ID after creating it")
    func returnsStoredGeneratedID() {
        let firstID = provider.getOrCreate()
        let secondID = provider.getOrCreate()

        #expect(firstID == generatedUUID.uuidString)
        #expect(secondID == firstID)
    }
}
