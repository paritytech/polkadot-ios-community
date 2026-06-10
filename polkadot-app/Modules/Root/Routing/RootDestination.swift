import Foundation

enum RootDestination: Equatable {
    case selectTheme
    case onboarding
    case restoreFromCloud
    case usernameCheck
    case dashboard
    case web3SummitSpa
    case web3SummitEnded
    case web3SummitNotStarted
    case jailbroken
    case broken
}

extension RootDestination {
    var impliesEstablishedUser: Bool {
        switch self {
        case .dashboard,
             .web3SummitSpa,
             .web3SummitEnded,
             .web3SummitNotStarted:
            true
        default:
            false
        }
    }
}
