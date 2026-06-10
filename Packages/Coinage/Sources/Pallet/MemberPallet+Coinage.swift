import Foundation
import Individuality

extension MembersPallet.RingPosition {
    var onchainState: Voucher.OnChainState {
        guard let ringIndex else {
            return .onboarding
        }

        return .inRecycler(Voucher.Recycler(index: ringIndex))
    }
}
