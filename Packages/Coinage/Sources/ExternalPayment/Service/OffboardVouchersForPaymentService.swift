import BigInt
import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import SubstrateSdk
import SubstrateOperation
import SubstrateSdkExt

/// Executes the offboarding flow: submits one extrinsic per recycler group
/// and records state changes via ``ExternalPaymentTransferContext``.
///
/// Each group's call must independently satisfy the pallet invariant:
/// `input_value (= coin_value * alias_count) == external_asset_amount + sum(loaded_coin_values)`
///
/// Groups with surplus use `unload_recycler_into_external_asset_and_loaded_coins`.
/// Groups without surplus use `unload_recycler_into_external_asset`.
final class OffboardVouchersForPaymentService {
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let voucherAllocator: any VoucherAllocating
    private let recyclerLoader: RecyclerReadinessLoading
    private let durability: any DurabilityServicing
    private let originFactory: OriginCreating
    private let blockNumberProvider: BlockInfoProviding
    private let denominationContext: DenominationBreakdownContext
    private let logger: SDKLoggerProtocol?

    init(
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherAllocator: any VoucherAllocating,
        recyclerLoader: RecyclerReadinessLoading,
        durability: any DurabilityServicing,
        originFactory: OriginCreating,
        blockNumberProvider: BlockInfoProviding,
        denominationContext: DenominationBreakdownContext,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherAllocator = voucherAllocator
        self.recyclerLoader = recyclerLoader
        self.durability = durability
        self.originFactory = originFactory
        self.blockNumberProvider = blockNumberProvider
        self.denominationContext = denominationContext
        self.logger = logger
    }

    func execute(
        payment: ExternalPayment,
        vouchers: [Voucher],
        transferContext: ExternalPaymentTransferContext
    ) async throws {
        guard !vouchers.isEmpty else { throw OffboardVouchersForPaymentError.emptyVouchers }
        guard !vouchers.contains(where: { $0.recycler == nil }) else {
            throw OffboardVouchersForPaymentError.missingRecyclerInfo
        }

        try await transferContext.reserve(vouchers: vouchers)

        do {
            try await executeSubmissions(
                payment: payment,
                vouchers: vouchers,
                transferContext: transferContext
            )
        } catch {
            await transferContext.revert()
            throw error
        }
    }
}

// MARK: - Submission Pipeline

private extension OffboardVouchersForPaymentService {
    func executeSubmissions(
        payment: ExternalPayment,
        vouchers: [Voucher],
        transferContext: ExternalPaymentTransferContext
    ) async throws {
        let groups = groupVouchers(vouchers)

        let details = try await buildGroupDetails(
            groups: groups,
            paymentAmount: payment.amountInPlanks
        )

        let blockHash = try await blockNumberProvider.fetchCurrentHash()

        let origins = try await originFactory.createAsUnloadTokenOrigins(
            voucherGroups: details.map(\.group.vouchers),
            currentDate: Date(),
            blockHash: blockHash
        )

        let keys = details.map(\.group.key)
        let revisions = try await recyclerLoader.fetchRevisions(for: keys, blockHash: blockHash)

        // Build full submissions with revision and destination
        var submissions: [GroupSubmission] = []
        var allSurplusVouchers: [Voucher] = []

        for (detail, origin) in zip(details, origins) {
            guard let revision = revisions[detail.group.key] else {
                throw OffboardVouchersForPaymentError.unexpectedEmptyRevision(detail.group.key)
            }

            allSurplusVouchers.append(contentsOf: detail.surplusVouchers)

            submissions.append(GroupSubmission(
                details: detail,
                revision: revision,
                destination: payment.destination,
                origin: origin
            ))
        }

        // Save surplus vouchers as pendingOnboarding via transfer context
        try await transferContext.savePendingOnboarding(vouchers: allSurplusVouchers)

        // Submit one extrinsic per group concurrently
        typealias GroupResult = Result<GroupSuccess, Error>

        let results: [GroupResult] = await withTaskGroup(of: GroupResult.self) { taskGroup in
            for submission in submissions {
                taskGroup.addTask {
                    do {
                        try await self.submitGroup(submission)
                        return .success(GroupSuccess(
                            spentVouchers: submission.details.group.vouchers,
                            newVouchers: submission.details.surplusVouchers
                        ))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var collected: [GroupResult] = []
            for await result in taskGroup {
                collected.append(result)
            }
            return collected
        }

        // Record on-chain changes locally per group
        var collectedErrors: [Error] = []

        for groupResult in results {
            switch groupResult {
            case let .success(success):
                do {
                    try await transferContext.process(
                        spentVouchers: success.spentVouchers,
                        newVouchers: success.newVouchers
                    )
                } catch {
                    logger?.error("Failed to record offboard locally: \(error)")
                    collectedErrors.append(error)
                }
            case let .failure(error):
                logger?.error("Offboard group failed: \(error)")
                collectedErrors.append(error)
            }
        }

        if !collectedErrors.isEmpty {
            throw OffboardVouchersForPaymentError.submissionFailed(collectedErrors)
        }

        durability.startRecoveryPass()
    }
}

// MARK: - Models

private extension OffboardVouchersForPaymentService {
    struct VoucherGroup {
        let key: RecyclerKey
        let vouchers: [Voucher]
    }

    struct GroupDetails {
        let group: VoucherGroup
        let externalAssetAmount: Balance
        let surplusVouchers: [Voucher]
    }

    struct GroupSubmission {
        let details: GroupDetails
        let revision: UInt32
        let destination: AccountId
        let origin: any ExtrinsicOriginDefining
    }

    struct GroupSuccess {
        let spentVouchers: [Voucher]
        let newVouchers: [Voucher]
    }
}

// MARK: - Per-Group Calculation

private extension OffboardVouchersForPaymentService {
    func buildGroupDetails(
        groups: [VoucherGroup],
        paymentAmount: Balance
    ) async throws -> [GroupDetails] {
        var remainingPayment = paymentAmount
        var result: [GroupDetails] = []

        for group in groups {
            let groupInput = group.vouchers.reduce(Balance(0)) {
                $0 + denominationContext.valueInPlanks(for: $1.exponent)
            }

            let groupExternalAsset = min(remainingPayment, groupInput)
            remainingPayment -= groupExternalAsset
            let groupSurplus = groupInput - groupExternalAsset

            let surplusVouchers = try await allocateSurplusVouchers(surplus: groupSurplus)

            result.append(GroupDetails(
                group: group,
                externalAssetAmount: groupExternalAsset,
                surplusVouchers: surplusVouchers
            ))
        }

        return result
    }
}

// MARK: - Grouping

private extension OffboardVouchersForPaymentService {
    func groupVouchers(_ vouchers: [Voucher]) -> [VoucherGroup] {
        var grouped: [RecyclerKey: [Voucher]] = [:]
        for voucher in vouchers {
            guard let recycler = voucher.recycler else { continue }
            let key = RecyclerKey(exponent: voucher.exponent, index: recycler.index)
            grouped[key, default: []].append(voucher)
        }
        return grouped.map { VoucherGroup(key: $0.key, vouchers: $0.value) }
    }
}

// MARK: - Surplus

private extension OffboardVouchersForPaymentService {
    func allocateSurplusVouchers(surplus: Balance) async throws -> [Voucher] {
        guard surplus > 0 else { return [] }

        guard let surplusDecimal = Decimal.fromSubstrateAmount(
            surplus,
            precision: denominationContext.precision
        ) else {
            return []
        }

        let denominations = denominationContext.breakdown(amount: surplusDecimal)
        var vouchers: [Voucher] = []

        for denomination in denominations {
            let voucher = try await voucherAllocator.allocate(exponent: denomination.exponent)
            vouchers.append(voucher)
        }

        return vouchers
    }
}

// MARK: - Submission

private extension OffboardVouchersForPaymentService {
    func submitGroup(_ submission: GroupSubmission) async throws {
        let aliases = try submission.details.group.vouchers.map {
            try voucherKeyFactory.createKeyManager(for: $0)
                .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
        }

        let key = submission.details.group.key

        let result = try await durability.submit(
            inputs: submission.details.group.vouchers.map { .recyclerVoucher($0.derivationIndex) },
            outputs: submission.details.surplusVouchers
                .map { .recyclerVoucher($0.derivationIndex) },
            builder: { builder in
                if submission.details.surplusVouchers.isEmpty {
                    let call = self.buildExternalAssetCall(aliases: aliases, key: key, submission: submission)
                    return try builder.adding(call: call.callAsFunction())
                } else {
                    let call = try self.buildExternalAssetAndVouchersCall(
                        aliases: aliases,
                        key: key,
                        submission: submission
                    )

                    return try builder.adding(call: call.callAsFunction())
                }
            },
            origin: submission.origin
        )

        switch result.submission.status {
        case .success:
            logger?.debug("Offboard extrinsic succeeded for key \(key)")
        case let .failure(error):
            logger?.error("Offboard extrinsic failed for key \(key): \(error.error)")
            throw error.error
        }
    }

    func buildExternalAssetCall(
        aliases: [Data],
        key: RecyclerKey,
        submission: GroupSubmission
    ) -> CoinagePallet.Calls.UnloadRecyclerIntoExternalAsset {
        CoinagePallet.Calls.UnloadRecyclerIntoExternalAsset(
            aliases: aliases,
            value: Int8(key.exponent),
            index: key.index,
            revision: submission.revision,
            to: submission.destination
        )
    }

    func buildExternalAssetAndVouchersCall(
        aliases: [Data],
        key: RecyclerKey,
        submission: GroupSubmission
    ) throws -> CoinagePallet.Calls.UnloadRecyclerIntoExternalAssetAndLoadedCoins {
        let loadedCoinEntries = try submission.details.surplusVouchers.map { voucher in
            let memberKey = try voucherKeyFactory.derivePublicKey(for: voucher)
            return CoinagePallet.Calls.UnloadRecyclerIntoExternalAssetAndLoadedCoins.LoadedCoin(
                coinValue: Int8(voucher.exponent),
                memberKey: memberKey
            )
        }

        return CoinagePallet.Calls.UnloadRecyclerIntoExternalAssetAndLoadedCoins(
            aliases: aliases,
            value: Int8(key.exponent),
            index: key.index,
            revision: submission.revision,
            to: submission.destination,
            externalAssetAmount: submission.details.externalAssetAmount,
            loadedCoins: loadedCoinEntries
        )
    }
}
