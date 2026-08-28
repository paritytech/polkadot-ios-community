import Foundation
import BandersnatchApi
import SubstrateSdk
import ExtrinsicService
import StructuredConcurrency
import BigInt
import KeyDerivation
import Keystore_iOS
import SDKLogger
import Operation_iOS

public protocol VoucherServiceProtocol: Sendable {
    func load(
        amount: BigUInt,
        externalAssetHolder: any WalletManaging,
        breakdownContext: DenominationBreakdownContext
    ) async throws

    /// Fetch all vouchers from the repository.
    func fetchAll() async throws -> [Voucher]

    /// Fetch all vouchers paired with their derived durability overlay.
    func fetchAllTracked() async throws -> [TrackedVoucher]

    func fetchAvailableInRecycler() async throws -> [Voucher]

    /// Save vouchers to the repository (upsert semantics).
    func save(vouchers: [Voucher]) async throws

    /// Delete vouchers by their string identifiers.
    func delete(identifiers: [String]) async throws
}

public final class VoucherService: @unchecked Sendable {
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let trackedVoucherRepository: AnyDataProviderRepository<TrackedVoucher>
    private let voucherLoaderFactory: VoucherLoaderFactoryProtocol

    public init(
        voucherRepository: AnyDataProviderRepository<Voucher>,
        trackedVoucherRepository: AnyDataProviderRepository<TrackedVoucher>,
        voucherLoaderFactory: VoucherLoaderFactoryProtocol
    ) {
        self.voucherRepository = voucherRepository
        self.trackedVoucherRepository = trackedVoucherRepository
        self.voucherLoaderFactory = voucherLoaderFactory
    }
}

extension VoucherService: VoucherServiceProtocol {
    public func load(
        amount: BigUInt,
        externalAssetHolder: any WalletManaging,
        breakdownContext: DenominationBreakdownContext
    ) async throws {
        let loader = try voucherLoaderFactory.makeLoader(for: externalAssetHolder)
        // Vouchers are persisted by the allocator as they are minted.
        _ = try await loader.load(amount: amount, breakdownContext: breakdownContext)
    }

    public func fetchAll() async throws -> [Voucher] {
        try await voucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }

    public func fetchAllTracked() async throws -> [TrackedVoucher] {
        try await trackedVoucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }

    public func fetchAvailableInRecycler() async throws -> [Voucher] {
        try await voucherRepository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .filter(\.remoteState.isInRecycler)
    }

    public func save(vouchers: [Voucher]) async throws {
        guard !vouchers.isEmpty else { return }
        try await voucherRepository.saveOperation({ vouchers }, { [] }).asyncExecute()
    }

    public func delete(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await voucherRepository.saveOperation({ [] }, { identifiers }).asyncExecute()
    }
}
