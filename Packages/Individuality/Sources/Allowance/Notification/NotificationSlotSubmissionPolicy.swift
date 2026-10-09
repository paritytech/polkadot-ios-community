import DurableTransactions
@preconcurrency import ExtrinsicService
import Foundation
import IssueMonitoring
import os
import SDKLogger
import StructuredConcurrency
import SubstrateSdk

/// Builds notification slot claims. Every build picks a free seq of the current period, so a claim that
/// collided on its seq, outlived its period or expired lands on a different slot when built again.
public final class NotificationSlotSubmissionPolicy: DurableSubmissionPolicy, @unchecked Sendable {
    public let chainId: ChainId

    private let picker: NotificationSeqPicker
    private let reservations: NotificationSeqReservations
    private let serialQueue: SerialOperationQueue
    private let originFactory: AsResourcesOriginCreating
    private let factory: any DurableTxMaking
    private let parameters: NotificationParametersProviding
    private let issueReporter: IssueReporting
    private let logger: SDKLoggerProtocol
    private let failuresByClaim = OSAllocatedUnfairLock<[DurableTxId: Int]>(initialState: [:])
    private let consecutivePrepareFailures = OSAllocatedUnfairLock(initialState: 0)

    public init(
        dependencies: NotificationSlotDependencies,
        originFactory: AsResourcesOriginCreating,
        factory: any DurableTxMaking
    ) {
        chainId = dependencies.chainId
        picker = dependencies.picker
        reservations = dependencies.reservations
        serialQueue = dependencies.serialQueue
        parameters = dependencies.parameters
        issueReporter = dependencies.issueReporter
        logger = dependencies.logger
        self.originFactory = originFactory
        self.factory = factory
    }

    // Unbounded on purpose: a rebuild re-picks period and seq, so no failure repeats on the same effects.
    public func canRetry(_ entry: DurableTxEntry, params _: Data, failure: DurableFailureKind) async -> Bool {
        logger.info("Notification slot claim \(entry.id) failed (\(failure)); rebuilding on a fresh seq")
        reportIfFailing(entry.id, failure: failure)
        return true
    }

    public func prepareSubmission(
        _ transactions: [ScheduledDurableTx]
    ) async throws -> [DurableTxId: SubmissionPreparation] {
        do {
            let preparations = try await prepare(transactions)
            consecutivePrepareFailures.withLock { $0 = 0 }
            return preparations
        } catch {
            reportIfUnbuildable(error)
            throw error
        }
    }
}

private extension NotificationSlotSubmissionPolicy {
    func prepare(_ transactions: [ScheduledDurableTx]) async throws -> [DurableTxId: SubmissionPreparation] {
        let period = try await parameters.currentPeriod()
        var preparations: [DurableTxId: SubmissionPreparation] = [:]

        for transaction in transactions {
            let target = transaction.policy.params

            guard let slot = try await reserveSlot(for: target, period: period) else {
                logger.warning("No free notification slot in period \(period); giving up claim \(transaction.id)")
                issueReporter.report(
                    CriticalIssue(
                        flow: NotificationSlotIssue.flow,
                        kind: "slot-claim-gave-up",
                        counters: ["period": Int(period)]
                    ),
                    onceFor: "slot-claim-gave-up-\(period)"
                )
                preparations[transaction.id] = .giveUp
                continue
            }

            preparations[transaction.id] = try await .ready(build(slot, for: target))
        }

        return preparations
    }

    func reportIfFailing(_ claim: DurableTxId, failure: DurableFailureKind) {
        let failures = failuresByClaim.withLock { counts in
            counts[claim, default: 0] += 1
            return counts[claim, default: 0]
        }

        guard failures == NotificationSlotIssue.failingClaimThreshold else { return }

        issueReporter.report(
            CriticalIssue(
                flow: NotificationSlotIssue.flow,
                kind: "slot-claim-failing",
                counters: [
                    "failures": failures,
                    "failureKind": DurableFailureKind.allCases.firstIndex(of: failure) ?? -1
                ]
            ),
            onceFor: "slot-claim-failing-\(claim)"
        )
    }

    func reportIfUnbuildable(_ error: Error) {
        let failures = consecutivePrepareFailures.withLock { count in
            count += 1
            return count
        }

        guard failures == NotificationSlotIssue.unbuildableClaimThreshold else { return }

        issueReporter.report(
            CriticalIssue(flow: NotificationSlotIssue.flow, kind: "slot-claim-unbuildable", error: error),
            onceFor: "slot-claim-unbuildable-\(String(reflecting: type(of: error)))"
        )
    }

    /// Keeps the slot reserved at scheduling while it is still unregistered, otherwise moves to a free one.
    func reserveSlot(for target: AccountId, period: UInt32) async throws -> NotificationSlot? {
        try await serialQueue.run { [picker, reservations, logger] in
            let free = try await picker.freeSlots(period: period, forTarget: target)
            let reservedKey = reservations.reserved(for: target)

            guard let slot = free.first(where: { $0.key == reservedKey }) ?? free.first else {
                reservations.release(target)
                return nil
            }

            try reservations.reserve(slot.key, for: target)
            logger.debug("Notification claim for \(target.toHex()) on seq \(slot.seq) of period \(slot.period)")

            return slot
        }
    }

    func build(_ slot: NotificationSlot, for target: AccountId) async throws -> ExtrinsicBuiltModel {
        let origin = try await originFactory.createNotificationOrigin(
            personOrigin: slot.personOrigin,
            period: slot.period,
            seq: slot.seq,
            chain: chainId
        )

        let call = ResourcesPallet.SetNotificationStatementAccountForSequenceCall(
            reference: ResourcesPallet.NotificationReference(period: slot.period, seq: slot.seq),
            accountId: target
        )

        let request = DurableTxRequest(builder: { try $0.adding(call: call()) }, origin: origin)

        guard let model = try await factory.makeExtrinsics([request], chainId: chainId).first else {
            throw DurableTxError.buildIncomplete
        }

        return model
    }
}
