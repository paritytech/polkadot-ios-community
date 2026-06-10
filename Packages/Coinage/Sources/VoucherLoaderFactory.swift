import Foundation
import ExtrinsicService
import KeyDerivation
import SDKLogger
import SubstrateSdk

public protocol VoucherLoaderFactoryProtocol {
    func makeLoader(for externalAssetHolder: any WalletManaging) throws -> VoucherLoaderProtocol
}

final class VoucherLoaderFactory: VoucherLoaderFactoryProtocol {
    private let allocator: any VoucherAllocating
    private let keypairFactory: any VoucherKeyDeriving
    private let extrinsicSubmitMonitor: any ExtrinsicSubmitMonitorFactoryProtocol
    private let originCreating: OriginCreating
    private let runtimeService: RuntimeCodingServiceProtocol
    private let chain: ChainProtocol
    private let logger: (any SDKLoggerProtocol)?

    init(
        allocator: any VoucherAllocating,
        keypairFactory: any VoucherKeyDeriving,
        extrinsicSubmitMonitor: any ExtrinsicSubmitMonitorFactoryProtocol,
        originCreating: OriginCreating,
        runtimeService: RuntimeCodingServiceProtocol,
        chain: ChainProtocol,
        logger: (any SDKLoggerProtocol)?
    ) {
        self.allocator = allocator
        self.keypairFactory = keypairFactory
        self.extrinsicSubmitMonitor = extrinsicSubmitMonitor
        self.originCreating = originCreating
        self.runtimeService = runtimeService
        self.chain = chain
        self.logger = logger
    }

    func makeLoader(for externalAssetHolder: any WalletManaging) throws -> VoucherLoaderProtocol {
        let account = try externalAssetHolder.fetchAccount(for: chain)
        let origin = try originCreating.createInfallibleUnpaidSignedOrigin(for: externalAssetHolder)

        return VoucherLoader(
            accountId: account.accountId,
            origin: origin,
            allocator: allocator,
            keypairFactory: keypairFactory,
            extrinsicSubmitMonitor: extrinsicSubmitMonitor,
            runtimeService: runtimeService,
            logger: logger
        )
    }
}
