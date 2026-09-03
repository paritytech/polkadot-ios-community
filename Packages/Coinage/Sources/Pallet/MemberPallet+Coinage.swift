import Foundation
import Individuality

extension MembersPallet.RingPosition {
    var onchainState: Voucher.OnChainState {
        guard let ringIndex else {
            return .onboarding
        }

        // TODO: Find consumers and rewrite that logic to provide proper members count
        return .inRecycler(Voucher.Recycler(index: ringIndex, membersCount: 0))
    }
}
