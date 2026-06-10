import Foundation

enum Web3SummitDestination: Equatable {
    case main
    case spa
    case ended
}

struct Web3SummitGate {
    private let modeProvider: Web3SummitGateModeProviding
    private let verifiedStorage: Web3SummitVerifiedStoring

    init(
        modeProvider: Web3SummitGateModeProviding,
        verifiedStorage: Web3SummitVerifiedStoring
    ) {
        self.modeProvider = modeProvider
        self.verifiedStorage = verifiedStorage
    }

    func decide() -> Web3SummitDestination {
        switch modeProvider.current() {
        case .ended:
            .ended
        case .verificationDisabled:
            .main
        case .verificationEnabled,
             .verificationEnabledSkippable:
            verifiedStorage.isVerified() ? .main : .spa
        }
    }

    var isSkippable: Bool {
        modeProvider.current() == .verificationEnabledSkippable
    }
}

extension Web3SummitGate {
    static func makeDefault() -> Web3SummitGate {
        Web3SummitGate(
            modeProvider: Web3SummitGateModeProvider(remoteConfig: FirebaseFacade.shared),
            verifiedStorage: Web3SummitVerifiedStorage()
        )
    }
}
