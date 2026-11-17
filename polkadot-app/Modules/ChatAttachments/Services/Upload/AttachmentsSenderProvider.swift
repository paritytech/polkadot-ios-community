import Foundation
import KeyDerivation
import Products

protocol AttachmentsSenderProviding {
    func getWallet() async throws -> WalletManaging
    /// Key reference of the sender wallet, stored with its allowance so the slot can be handed over.
    func getSignerKeyId() throws -> String
}

final class AttachmentsSenderProvider {
    let tldProvider: DotNsTldProviding
    let entropyManager: RootEntropyManaging

    init(
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        tldProvider: DotNsTldProviding = DotNsTldProviderFacade.shared
    ) {
        self.entropyManager = entropyManager
        self.tldProvider = tldProvider
    }
}

extension AttachmentsSenderProvider: AttachmentsSenderProviding {
    func getWallet() async throws -> WalletManaging {
        try DynamicDerivedWallet(derivationPath: getSignerKeyId(), entropyManager: entropyManager)
    }

    func getSignerKeyId() throws -> String {
        try ChatKeyPaths.hop(tld: tldProvider.currentTldOrError())
    }
}
