import Foundation

enum SynchronizableKeychainTag {
    static let domain = "io.polkadotapp.cloud.keychain"

    // New-chain launch reset: the `.v2` suffix makes the app look under a new iCloud tag, find no
    // backup, and route to fresh Onboarding instead of Restore-from-iCloud. The user's pre-relaunch
    // mnemonic stays under the old tag in their iCloud, untouched — rename only, never delete.
    static var walletEntropy: String {
        domain + "." + "wallet.entropy.v2"
    }
}
