import Foundation
import BandersnatchApi
import SubstrateSdk
import Individuality
import ExtrinsicService
import StructuredConcurrency
import BigInt
import SDKLogger
import Operation_iOS

public protocol VoucherLoaderProtocol {
    func load(
        amount: BigUInt,
        breakdownContext: DenominationBreakdownContext
    ) async throws -> [Voucher]
}

public final class VoucherLoader: VoucherLoaderProtocol {
    private let accountId: AccountId
    private let origin: any ExtrinsicOriginDefining
    private let allocator: any VoucherAllocating
    private let keypairFactory: any VoucherKeyDeriving
    private let extrinsicSubmitMonitor: any ExtrinsicSubmitMonitorFactoryProtocol
    private let runtimeService: RuntimeCodingServiceProtocol
    private let logger: (any SDKLoggerProtocol)?

    init(
        accountId: AccountId,
        origin: any ExtrinsicOriginDefining,
        allocator: any VoucherAllocating,
        keypairFactory: any VoucherKeyDeriving,
        extrinsicSubmitMonitor: any ExtrinsicSubmitMonitorFactoryProtocol,
        runtimeService: RuntimeCodingServiceProtocol,
        logger: SDKLoggerProtocol?
    ) {
        self.accountId = accountId
        self.origin = origin
        self.allocator = allocator
        self.keypairFactory = keypairFactory
        self.extrinsicSubmitMonitor = extrinsicSubmitMonitor
        self.runtimeService = runtimeService
        self.logger = logger
    }

    public func load(
        amount: BigUInt,
        breakdownContext: DenominationBreakdownContext
    ) async throws -> [Voucher] {
        let denominations = breakdownContext.breakdown(amountInPlanks: amount)

        let pairs = try await runtimeCalls(for: denominations)

        logger?.debug("Breakdown \(amount) into \(pairs.count) calls")

        guard !pairs.isEmpty else { return [] }

        let maxBatchSize = try await runtimeService.fetchConstant(
            path: CoinagePallet.Constants.maxBatchUnpaidLoad(),
            type: UInt32.self
        )

        let chunkSize = Int(maxBatchSize)
        let chunks = stride(from: 0, to: pairs.count, by: chunkSize).map {
            Array(pairs[$0 ..< min($0 + chunkSize, pairs.count)])
        }

        let builder: ExtrinsicBuilderIndexedClosure = { builder, index in
            let batchCall = CoinagePallet.Calls.LoadExternalAssetUnpaidBatch(items: chunks[index].map(\.1))
            return try builder.adding(call: batchCall.callAsFunction())
        }

        let retriableResult = try await extrinsicSubmitMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: builder,
            origin: origin,
            indexes: IndexSet(0 ..< chunks.count),
            params: .empty
        ).asyncExecute()

        return retriableResult.results.flatMap { indexedResult in
            switch indexedResult.result {
            case let .success(submission):
                switch submission.status {
                case .success:
                    logger?.debug("Batch loaded \(chunks[indexedResult.index].count) vouchers: success")
                    return chunks[indexedResult.index].map(\.0)
                case let .failure(error):
                    logger?.error("Batch \(indexedResult.index) failed on-chain: \(error)")
                    return []
                }
            case let .failure(error):
                logger?.error("Batch \(indexedResult.index) submission failed: \(error)")
                return []
            }
        }
    }

    private func runtimeCalls(
        for denominations: [Denomination]
    ) async throws -> [(Voucher, CoinagePallet.Calls.LoadExternalAssetUnpaidBatch.UnpaidLoadInput)] {
        typealias Pair = (Voucher, CoinagePallet.Calls.LoadExternalAssetUnpaidBatch.UnpaidLoadInput)
        return try await withThrowingTaskGroup(of: Pair.self) { group in
            denominations.forEach { denomination in
                group.addTask {
                    let voucher = try await self.allocator.allocate(exponent: denomination.exponent)
                    let publicKey = try self.keypairFactory.derivePublicKey(for: voucher)
                    let keyManager = try self.keypairFactory.createKeyManager(for: voucher)

                    let proof = try keyManager.sign(self.accountId)

                    let input = CoinagePallet.Calls.LoadExternalAssetUnpaidBatch.UnpaidLoadInput(
                        value: voucher.exponent,
                        preservation: .expendable,
                        memberKey: publicKey,
                        proofOfOwnership: proof
                    )

                    return (voucher, input)
                }
            }

            var results: [Pair] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
}

extension ExtrinsicSubmissionParams {
    static var empty: Self {
        ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
    }
}

extension ExtrinsicIndexedSubmissionParams {
    static var empty: Self {
        ExtrinsicIndexedSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
    }
}
