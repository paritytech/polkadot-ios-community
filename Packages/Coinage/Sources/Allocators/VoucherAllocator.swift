import Foundation
import SubstrateSdk
import NovaCrypto
import Operation_iOS

protocol VoucherAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Voucher
}

/// Actor isolation serialises the index counter's read-modify-write, so a single shared instance is
/// the only safe configuration — do not create more than one against the same index store.
actor VoucherAllocator: VoucherAllocating {
    private let storage: CoinageIndexstoreProtocol
    private let delayProvider: VoucherDelayProviderProtocol
    private let voucherRepository: AnyDataProviderRepository<Voucher>

    init(
        storage: CoinageIndexstoreProtocol,
        delayProvider: VoucherDelayProviderProtocol,
        voucherRepository: AnyDataProviderRepository<Voucher>
    ) {
        self.storage = storage
        self.delayProvider = delayProvider
        self.voucherRepository = voucherRepository
    }

    /// Allocates a new voucher index and persists the voucher, so it exists in the database from the
    /// moment it is minted (matching the coin allocator and the Android model).
    func allocate(exponent: Int16) async throws -> Voucher {
        let index = try storage.getNextIndex()
        let delay = delayProvider.timeInterval()
        let allocatedAt = Date.now

        let voucher = Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: allocatedAt,
            readyAt: allocatedAt.addingTimeInterval(delay)
        )
        try await voucherRepository.saveOperation({ [voucher] }, { [] }).asyncExecute()
        return voucher
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
