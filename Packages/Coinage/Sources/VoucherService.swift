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

public protocol VoucherServiceProtocol {
    func load(
        amount: BigUInt,
        externalAssetHolder: any WalletManaging,
        breakdownContext: DenominationBreakdownContext
    ) async throws

    /// Fetch all vouchers from the repository.
    func fetchAll() async throws -> [Voucher]

    func fetchAvailableInRecycler() async throws -> [Voucher]

    /// Save vouchers to the repository (upsert semantics).
    func save(vouchers: [Voucher]) async throws

    /// Delete vouchers by their string identifiers.
    func delete(identifiers: [String]) async throws

    /// Mark vouchers as available by setting localState to .available.
    func markAvailable(identifiers: [String]) async throws

    /// Mark vouchers as pending transfer by setting localState to .pendingTransfer.
    func markPendingTransfer(identifiers: [String]) async throws

    /// Mark vouchers as pending onboarding by setting localState to .pendingOnboarding.
    func markPendingOnboarding(identifiers: [String]) async throws
}

public final class VoucherService {
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let voucherLoaderFactory: VoucherLoaderFactoryProtocol

    public init(
        voucherRepository: AnyDataProviderRepository<Voucher>,
        voucherLoaderFactory: VoucherLoaderFactoryProtocol
    ) {
        self.voucherRepository = voucherRepository
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
        let vouchers = try await loader.load(amount: amount, breakdownContext: breakdownContext)
        try await voucherRepository.saveOperation({ vouchers }, { [] }).asyncExecute()
    }

    public func fetchAll() async throws -> [Voucher] {
        try await voucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }

    public func fetchAvailableInRecycler() async throws -> [Voucher] {
        try await voucherRepository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .filter { $0.localState == .available && $0.remoteState.isInRecycler }
    }

    public func save(vouchers: [Voucher]) async throws {
        guard !vouchers.isEmpty else { return }
        try await voucherRepository.saveOperation({ vouchers }, { [] }).asyncExecute()
    }

    public func delete(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await voucherRepository.saveOperation({ [] }, { identifiers }).asyncExecute()
    }

    public func markAvailable(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        let all = try await voucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
        let updated = all
            .filter { identifiers.contains($0.identifier) }
            .map { $0.withLocalState(.available) }
        guard !updated.isEmpty else { return }
        try await voucherRepository.saveOperation({ updated }, { [] }).asyncExecute()
    }

    public func markPendingTransfer(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        let all = try await voucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
        let updated = all
            .filter { identifiers.contains($0.identifier) }
            .map { $0.withLocalState(.pendingTransfer) }
        guard !updated.isEmpty else { return }
        try await voucherRepository.saveOperation({ updated }, { [] }).asyncExecute()
    }

    public func markPendingOnboarding(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        let all = try await voucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
        let updated = all
            .filter { identifiers.contains($0.identifier) }
            .map { $0.withLocalState(.pendingOnboarding) }
        guard !updated.isEmpty else { return }
        try await voucherRepository.saveOperation({ updated }, { [] }).asyncExecute()
    }
}
