import Foundation
import SubstrateSdk
import NovaCrypto

protocol VoucherAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Voucher
}

actor VoucherAllocator: VoucherAllocating {
    private let storage: CoinageIndexstoreProtocol
    private let delayProvider: VoucherDelayProviderProtocol

    init(
        storage: CoinageIndexstoreProtocol,
        delayProvider: VoucherDelayProviderProtocol
    ) {
        self.storage = storage
        self.delayProvider = delayProvider
    }

    /// Allocates a new voucher index, persists it, and derives the corresponding keypair.
    /// - Parameter exponent: The power-of-two denomination for the new coin.
    /// - Returns: A `Voucher` ready for use on-chain.
    func allocate(exponent: Int16) async throws -> Voucher {
        let index = try storage.getNextIndex()
        let delay = delayProvider.timeInterval()

        return Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: .now,
            readyAt: .now.addingTimeInterval(delay)
        )
    }
}

protocol VoucherDelayProviderProtocol {
    func timeInterval() -> TimeInterval
}

final class VoucherDelayProvider: VoucherDelayProviderProtocol {
    private let maxWaitTime: TimeInterval = CoinageConstants.maxVoucherWaitTime

    func timeInterval() -> TimeInterval {
        TimeInterval.random(in: 0 ... maxWaitTime)
    }
}
