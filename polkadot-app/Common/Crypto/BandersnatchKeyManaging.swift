import Foundation
import KeyDerivation

extension BandersnatchKeyManager {
    /// Full personhood ring-VRF key: `//peopl.dot//index_bytes(0)`.
    static func fullPerson(
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) -> BandersnatchKeyManager {
        BandersnatchKeyManager(
            entropyDeriver: RingVrfEntropyDeriver(domain: BuiltInProduct.personhood, index: 0),
            entropyManager: entropyManager
        )
    }

    /// Light personhood ring-VRF key: `//peopl.dot//index_bytes(1)`.
    static func litePerson(
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) -> BandersnatchKeyManager {
        BandersnatchKeyManager(
            entropyDeriver: RingVrfEntropyDeriver(domain: BuiltInProduct.personhood, index: 1),
            entropyManager: entropyManager
        )
    }
}
