import Foundation
import SubstrateSdk
import NovaCrypto
import Operation_iOS
import StructuredConcurrency

protocol VoucherAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Voucher
}

/// Hands out the next voucher item in the current installation: `max(item) + 1` over what is stored
/// there, so a previous installation's vouchers never move this installation's counter. The serial
/// queue keeps the read-then-save atomic across suspension points; a single shared instance is the
/// only safe configuration.
actor VoucherAllocator: VoucherAllocating {
    private let installationRepository: any CoinageInstallationRepositoryProtocol
    private let keyIndexQueries: any CoinageKeyIndexQuerying
    private let delayProvider: VoucherDelayProviderProtocol
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let keyFactory: any VoucherKeyDeriving
    private let queue = SerialOperationQueue()

    init(
        installationRepository: any CoinageInstallationRepositoryProtocol,
        keyIndexQueries: any CoinageKeyIndexQuerying,
        delayProvider: VoucherDelayProviderProtocol,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        keyFactory: any VoucherKeyDeriving
    ) {
        self.installationRepository = installationRepository
        self.keyIndexQueries = keyIndexQueries
        self.delayProvider = delayProvider
        self.voucherRepository = voucherRepository
        self.keyFactory = keyFactory
    }

    /// Allocates a new voucher index and persists the voucher — with its on-chain public key cached
    /// so the durability layer never re-derives it — from the moment it is minted.
    func allocate(exponent: Int16) async throws -> Voucher {
        try await queue.run { [self] in
            let index = try await nextIndex()
            let delay = delayProvider.timeInterval()
            let allocatedAt = Date.now

            let voucher = try Voucher(
                exponent: exponent,
                derivationIndex: index,
                allocatedAt: allocatedAt,
                readyAt: allocatedAt.addingTimeInterval(delay),
                publicKey: keyFactory.derivePublicKey(index: index)
            )
            try await voucherRepository.saveOperation({ [voucher] }, { [] }).asyncExecute()
            return voucher
        }
    }
}

private extension VoucherAllocator {
    func nextIndex() async throws -> CoinageKeyIndex {
        let installation = try await installationRepository.getOrCreateCurrent()
        let item = try await keyIndexQueries.maxVoucherItem(in: installation).map { $0 + 1 } ?? 0
        return CoinageKeyIndex(installation: installation, item: item)
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
