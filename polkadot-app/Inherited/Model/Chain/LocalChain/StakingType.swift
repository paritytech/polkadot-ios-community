import Foundation

enum StakingType: String, Codable, Equatable, Hashable {
    case relaychain
    case parachain
    case azero = "aleph-zero"
    case auraRelaychain = "aura-relaychain"
    case turing
    case nominationPools = "nomination-pools"
    case unsupported

    init(rawType: String?) {
        if let rawType, let value = StakingType(rawValue: rawType) {
            self = value
        } else {
            self = .unsupported
        }
    }

    func isMorePreferred(than stakingType: StakingType) -> Bool {
        StakingClass(stakingType: self).preferringRating < StakingClass(stakingType: stakingType).preferringRating
    }
}

enum StakingClass {
    case relaychain
    case parachain
    case nominationPools
    case unsupported

    // lesser better
    var preferringRating: UInt8 {
        switch self {
        case .relaychain:
            0
        case .parachain:
            1
        case .nominationPools:
            2
        case .unsupported:
            3
        }
    }

    init(stakingType: StakingType) {
        switch stakingType {
        case .relaychain,
             .azero,
             .auraRelaychain:
            self = .relaychain
        case .parachain,
             .turing:
            self = .parachain
        case .nominationPools:
            self = .nominationPools
        case .unsupported:
            self = .unsupported
        }
    }
}
