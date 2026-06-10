import Foundation
import KeyDerivation

extension BandersnatchKeyManager {
    static func fullPerson(
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) -> BandersnatchKeyManager {
        BandersnatchKeyManager(
            entropyDeriver: FullPersonBandersnatchDeriver(),
            entropyManager: entropyManager
        )
    }

    static func litePerson(
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) -> BandersnatchKeyManager {
        BandersnatchKeyManager(
            entropyDeriver: LitePersonBandersnatchDeriver(),
            entropyManager: entropyManager
        )
    }
}
