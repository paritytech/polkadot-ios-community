import Foundation

enum UserStorageVersion: String, CaseIterable {
    case version41 = "UserDataModel41"

    func nextVersion() -> UserStorageVersion? {
        switch self {
        case .version41:
            nil
        }
    }
}
