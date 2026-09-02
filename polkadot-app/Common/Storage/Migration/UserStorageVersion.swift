import Foundation

enum UserStorageVersion: String, CaseIterable {
    case version41 = "UserDataModel41"
    case version42 = "UserDataModel42"
    case version43 = "UserDataModel43"

    func nextVersion() -> UserStorageVersion? {
        switch self {
        case .version41:
            .version42
        case .version42:
            .version43
        case .version43:
            nil
        }
    }
}
