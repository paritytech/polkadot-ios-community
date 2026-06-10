import Foundation
import SubstrateSdk
import Individuality
import KeyDerivation

extension People {
    struct RegisteredData: Hashable {
        let mobRuleAlias: PeoplePallet.ContextualAlias
        let scoreAlias: PeoplePallet.ContextualAlias
        let resourcesAlias: PeoplePallet.ContextualAlias
        let personId: ProofOfInkPallet.PersonalId
        let source: RegisteredSource
        let liteUsername: Username
        let fullUsername: Username?
    }

    enum RegisteredSource: Hashable {
        case proofOfInk(ProofOfInkPallet.Person)
        case game
    }
}

extension People.RegisteredData {
    var isUsernameUpgradeAvailable: Bool {
        fullUsername == nil
    }
}

extension People.RegisteredSource {
    var isGameRecognizedPerson: Bool {
        self == .game
    }

    var isNotGameRecognizedPerson: Bool {
        !isGameRecognizedPerson
    }
}

enum GameAccountFactory {
    static func makeAccount(
        chain: ChainModel,
        registeredSource: People.RegisteredSource?
    ) -> AccountProtocol? {
        let wallet = makeWallet(for: registeredSource)
        return try? wallet.fetchAccount(for: chain)
    }

    static func makeWallet(for registeredSource: People.RegisteredSource?) -> WalletManaging {
        switch registeredSource {
        case .proofOfInk:
            SelectedWallet.scoreAlias
        case .game,
             nil:
            SelectedWallet.candidate
        }
    }

    static func makeWalletKeyId(for registeredSource: People.RegisteredSource?) -> String {
        switch registeredSource {
        case .proofOfInk:
            WalletDerivationPath.score
        case .game,
             nil:
            WalletDerivationPath.candidate
        }
    }
}
