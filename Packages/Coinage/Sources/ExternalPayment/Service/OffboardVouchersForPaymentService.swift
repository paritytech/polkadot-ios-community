import BigInt
import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import SubstrateSdk
import SubstrateOperation
import SubstrateSdkExt

/// Executes the offboarding flow: submits one extrinsic per recycler group.
/// The transaction layer tracks the spent voucher inputs and surplus outputs; the surplus vouchers are
/// already persisted by the allocator when minted, so no local state bookkeeping is required.
///
/// Each group's call must independently satisfy the pallet invariant:
/// `input_value (= coin_value * alias_count) == external_asset_amount + sum(loaded_coin_values)`
///
/// Groups with surplus use `unload_recycler_into_external_asset_and_loaded_coins`.
/// Groups without surplus use `unload_recycler_into_external_asset`.
final class OffboardVouchersForPaymentService {
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let voucherMinter: any VoucherMinting
    private let recyclerLoader: RecyclerReadinessLoading
    private let durability: any CoinageTxServicing
    private let originFactory: OriginCreating
    private let blockNumberProvider: BlockInfoProviding
    private let denominationContext: DenominationBreakdownContext
    private let logger: SDKLoggerProtocol?

    init(
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherMinter: any VoucherMinting,
        recyclerLoader: RecyclerReadinessLoading,
        durability: any CoinageTxServicing,
        originFactory: OriginCreating,
        blockNumberProvider: BlockInfoProviding,
        denominationContext: DenominationBreakdownContext,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherMinter = voucherMinter
        self.recyclerLoader = recyclerLoader
        self.durability = durability
        self.originFactory = originFactory
        self.blockNumberProvider = blockNumberProvider
        self.denominationContext = denominationContext
        self.logger = logger
    }

    func execute(
        payment: ExternalPayment,
        vouchers: [Voucher]
    ) async throws {
        guard !vouchers.isEmpty else { throw OffboardVouchersForPaymentError.emptyVouchers }
        guard !vouchers.contains(where: { $0.recycler == nil }) else {
            throw OffboardVouchersForPaymentError.missingRecyclerInfo
        }

        try await executeSubmissions(payment: payment, vouchers: vouchers)
    }
}

// MARK: - Submission Pipeline

private extension OffboardVouchersForPaymentService {
    func executeSubmissions(
        payment: ExternalPayment,
        vouchers: [Voucher]
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

        var submissions: [GroupSubmission] = []
        for (detail, origin) in zip(details, origins) {
            guard let revision = revisions[detail.group.key] else {
                throw OffboardVouchersForPaymentError.unexpectedEmptyRevision(detail.group.key)
            }

            submissions.append(GroupSubmission(
                details: detail,
                revision: revision,
                destination: payment.destination,
                origin: origin
            ))
        }

        // Fire-and-forget submit each group; registration claims its vouchers and records the surplus
        // outputs. Collect the entry ids so their outcomes can be awaited below.
        var entryIds: [CoinageTxId] = []
        var errors: [Error] = []
        for submission in submissions {
            do {
                try await entryIds.append(submitGroup(submission))
            } catch {
                logger?.error("Offboard group registration failed: \(error)")
                errors.append(error)
            }
        }

        // Await each group's terminal outcome via the durability layer, matching Android's
        // `awaitOutcome`: the state machine must not report the payment completed until the chain has.
        let outcomeErrors = await withTaskGroup(of: Error?.self) { taskGroup in
            for id in entryIds {
                taskGroup.addTask {
                    do {
                        try await self.awaitOutcome(of: id)
                        return nil
                    } catch {
                        self.logger?.error("Offboard group failed: \(error)")
                        return error
                    }
                }
            }

            var collected: [Error] = []
            for await error in taskGroup {
                if let error { collected.append(error) }
            }
            return collected
        }
        errors += outcomeErrors

        if !errors.isEmpty {
            throw OffboardVouchersForPaymentError.submissionFailed(errors)
        }

        durability.startRecoveryPass()
    }

    /// Awaits an entry's terminal status: returns on `finalizedSuccess`, throws on `failure`.
    func awaitOutcome(of id: CoinageTxId) async throws {
        for try await status in durability.subscribeTransactionStatus(id) {
            switch status {
            case .finalizedSuccess:
                return
            case .failure:
                throw OffboardVouchersForPaymentError.groupExecutionFailed(id)
            case .pending,
                 .pendingSuccess:
                continue
            }
        }
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
        return try await voucherMinter.mintVouchers(denominations.map(\.exponent))
    }
}

// MARK: - Submission

private extension OffboardVouchersForPaymentService {
    func submitGroup(_ submission: GroupSubmission) async throws -> CoinageTxId {
        let aliases = try submission.details.group.vouchers.map {
            try voucherKeyFactory.createKeyManager(for: $0)
                .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
        }

        let key = submission.details.group.key

        let id = try await durability.submitTransaction(
            request: CoinageTxRequest(
                inputs: submission.details.group.vouchers.map { .recyclerVoucher($0.derivationIndex, $0.publicKey) },
                outputs: submission.details.surplusVouchers
                    .map { .recyclerVoucher($0.derivationIndex, $0.publicKey) },
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
            ),
            groupId: nil
        )

        logger?.debug("Offboard extrinsic submitted for key \(key)")
        return id
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
        let loadedCoinEntries = submission.details.surplusVouchers.map { voucher in
            CoinagePallet.Calls.UnloadRecyclerIntoExternalAssetAndLoadedCoins.LoadedCoin(
                coinValue: Int8(voucher.exponent),
                memberKey: voucher.publicKey
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
