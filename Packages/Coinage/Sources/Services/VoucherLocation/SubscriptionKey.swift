import Foundation

enum SubscriptionKey: Hashable {
    case member(derivationIndex: DerivationIndex)
    case ringStatus(derivationIndex: DerivationIndex)
    case unloadedCount(derivationIndex: DerivationIndex)

    static let separator = ":"

    init?(mappingKey: String) {
        let components = mappingKey.split(separator: Self.separator)
        guard components.count >= 2 else { return nil }

        let type = components[0]

        switch type {
        case "m":
            guard let index = DerivationIndex(components[1]) else { return nil }
            self = .member(derivationIndex: index)
        case "rs":
            guard components.count == 2, let index = DerivationIndex(components[1]) else { return nil }
            self = .ringStatus(derivationIndex: index)
        case "uc":
            guard components.count == 2, let index = DerivationIndex(components[1]) else { return nil }
            self = .unloadedCount(derivationIndex: index)
        default:
            return nil
        }
    }

    var mappingKey: String {
        switch self {
        case let .member(index): ["m", "\(index)"].joined(separator: Self.separator)
        case let .ringStatus(index): ["rs", "\(index)"].joined(separator: Self.separator)
        case let .unloadedCount(index): ["uc", "\(index)"].joined(separator: Self.separator)
        }
    }
}
