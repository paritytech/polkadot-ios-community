import BigInt
import KeyDerivation
import ExtrinsicService
import Foundation
import os
@testable import Coinage

/// Serves a configurable tracked-voucher set; `load` is not supported (payments never load vouchers).
final class StubVoucherService: VoucherServiceProtocol, @unchecked Sendable {
    struct NotSupported: Error {}

    private let vouchers = OSAllocatedUnfairLock(initialState: [Voucher]())

    init(vouchers: [Voucher] = []) {
        set(vouchers: vouchers)
    }

    func set(vouchers: [Voucher]) {
        self.vouchers.withLock { $0 = vouchers }
    }

    func load(
        amount _: BigUInt,
        externalAssetHolder _: any WalletManaging,
        breakdownContext _: DenominationBreakdownContext,
        groupId _: CoinageTxGroupId?
    ) async throws -> [Voucher] {
        throw NotSupported()
    }

    func fetchVouchers(publicKeys: Set<PublicKey>) async throws -> [Voucher] {
        vouchers.withLock { $0 }.filter { publicKeys.contains($0.publicKey) }
    }

    func fetchAllTracked() async throws -> [TrackedVoucher] {
        vouchers.withLock { $0 }.map {
            TrackedVoucher(
                voucher: $0,
                state: CoinageAssetState(handedOff: false, consumerStatus: nil, minterStatus: nil)
            )
        }
    }
}
