import Foundation
import BandersnatchApi

public struct MembersProofParams {
    public let ringMembers: [MembersPallet.RingMember]
    public let ringSize: BandersnatchApi.RingDomainSize

    public init(
        ringMembers: [MembersPallet.RingMember],
        ringSize: BandersnatchApi.RingDomainSize
    ) {
        self.ringMembers = ringMembers
        self.ringSize = ringSize
    }
}
