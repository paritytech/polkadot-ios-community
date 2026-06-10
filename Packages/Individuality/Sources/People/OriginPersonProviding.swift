import Foundation
import SubstrateSdk
import KeyDerivation

public protocol OriginPersonProviding {
    func pickPersonOrigin() async throws -> PersonOrigin
}

public enum OriginPersonProviderError: Error {
    case noPersonsExist
}

// checks ring status of both lite and full person, prefers full one
public final class OriginPersonProvider {
    let liteVrfManager: BandersnatchKeyManaging
    let liteCollectionId: MembersPallet.CollectionIdentifier
    let fullVrfManager: BandersnatchKeyManaging
    let fullCollectionId: MembersPallet.CollectionIdentifier
    let memberStatusChecker: MembershipStatusChecking

    public init(
        liteVrfManager: BandersnatchKeyManaging,
        liteCollectionId: MembersPallet.CollectionIdentifier,
        fullVrfManager: BandersnatchKeyManaging,
        fullCollectionId: MembersPallet.CollectionIdentifier,
        memberStatusChecker: MembershipStatusChecking
    ) {
        self.liteVrfManager = liteVrfManager
        self.liteCollectionId = liteCollectionId
        self.fullVrfManager = fullVrfManager
        self.fullCollectionId = fullCollectionId
        self.memberStatusChecker = memberStatusChecker
    }
}

extension OriginPersonProvider: OriginPersonProviding {
    public func pickPersonOrigin() async throws -> PersonOrigin {
        let fullMemberKey = try fullVrfManager.getMemberKey()
        let liteMemberKey = try liteVrfManager.getMemberKey()

        let statuses = try await memberStatusChecker.checkStatuses(
            of: [
                .init(memberKey: fullMemberKey, collection: fullCollectionId),
                .init(memberKey: liteMemberKey, collection: liteCollectionId),
            ],
            blockHash: nil
        )

        if let fullRingIndex = statuses[fullMemberKey] {
            return .full(fullRingIndex, fullVrfManager)
        }

        if let liteRingIndex = statuses[liteMemberKey] {
            return .lite(liteRingIndex, liteVrfManager)
        }

        throw OriginPersonProviderError.noPersonsExist
    }
}
