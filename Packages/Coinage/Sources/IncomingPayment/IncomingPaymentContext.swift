import AsyncExtensions
import Foundation
import SDKLogger

/// Holds the in-flight incoming-payment claim tasks and each payment's current derived status,
/// mirroring `MixnetUploadContext`. Keyed by `groupId` (`"productId:paymentId"`) so payments from
/// different products never collide. Persists the terminal `processed` flag; status itself is never
/// persisted (it is derived from the durability group and cached in a per-payment subject).
actor IncomingPaymentContext {
    struct Pending {
        let groupId: CoinageTxGroupId
        let run: @Sendable () -> Task<Void, Never>
    }

    private let store: any IncomingPaymentStoring
    private let maxConcurrent: Int
    private let logger: SDKLoggerProtocol?

    private var tasks: [CoinageTxGroupId: Task<Void, Never>] = [:]
    private var subjects: [CoinageTxGroupId: AsyncCurrentValueSubject<IncomingPaymentStatus>] = [:]
    private var pending: [Pending] = []

    init(
        store: any IncomingPaymentStoring,
        maxConcurrent: Int = 5,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.maxConcurrent = maxConcurrent
        self.logger = logger
    }
}

// MARK: - Scheduling

extension IncomingPaymentContext {
    /// Starts (or queues, when at capacity) the claim for `groupId`. Dedups by `groupId` and seeds the
    /// status subject `.detecting`, so a subscriber attaching before the task reports sees detecting.
    func process(groupId: CoinageTxGroupId, run: @escaping @Sendable () -> Task<Void, Never>) {
        guard tasks[groupId] == nil, !pending.contains(where: { $0.groupId == groupId }) else {
            return
        }

        _ = subject(for: groupId)

        if tasks.count < maxConcurrent {
            tasks[groupId] = run()
        } else {
            pending.append(Pending(groupId: groupId, run: run))
        }
    }

    /// Reports a derived status. On a terminal status, marks the payment processed, frees the slot and
    /// starts the next queued claim. The subject is kept so its terminal value stays queryable.
    func report(_ status: IncomingPaymentStatus, for groupId: CoinageTxGroupId) async {
        subject(for: groupId).send(status)

        guard status.isTerminal else { return }

        do {
            try await store.markProcessed(groupId: groupId)
        } catch {
            logger?.error("Failed to mark incoming payment \(groupId) processed: \(error)")
        }

        tasks[groupId] = nil
        startNextIfPossible()
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        pending.removeAll()
    }
}

// MARK: - Status

extension IncomingPaymentContext {
    /// The live status stream for `groupId`, or `nil` when the context holds nothing for it (a cold
    /// subscribe to a processed record — the service derives the terminal status from durability).
    func liveStatusStream(for groupId: CoinageTxGroupId) -> AnyAsyncSequence<IncomingPaymentStatus>? {
        subjects[groupId]?.eraseToAnyAsyncSequence()
    }

    /// Seeds a subject with an externally derived status (e.g. a terminal status re-derived from
    /// durability for a processed record) and returns its stream.
    func seededStatusStream(
        _ status: IncomingPaymentStatus,
        for groupId: CoinageTxGroupId
    ) -> AnyAsyncSequence<IncomingPaymentStatus> {
        let subject = subject(for: groupId)
        subject.send(status)
        return subject.eraseToAnyAsyncSequence()
    }
}

// MARK: - Private

private extension IncomingPaymentContext {
    func subject(for groupId: CoinageTxGroupId) -> AsyncCurrentValueSubject<IncomingPaymentStatus> {
        if let subject = subjects[groupId] {
            return subject
        }
        let subject = AsyncCurrentValueSubject<IncomingPaymentStatus>(.detecting)
        subjects[groupId] = subject
        return subject
    }

    func startNextIfPossible() {
        while tasks.count < maxConcurrent, !pending.isEmpty {
            let next = pending.removeFirst()
            tasks[next.groupId] = next.run()
        }
    }
}
