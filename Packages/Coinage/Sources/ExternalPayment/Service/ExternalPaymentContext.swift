import Foundation
import SDKLogger

/// Actor managing sequential payment execution with a pending queue.
///
/// Stores pending tasks with their execution closures. Only one payment
/// runs at a time; when it completes the next pending is started automatically.
actor ExternalPaymentContext {
    struct Pending {
        let paymentId: String
        let onExecute: @Sendable () -> Task<Void, Never>
    }

    private(set) var currentPaymentId: String?
    private var currentTask: Task<Void, Never>?
    private var pendingTasks: [Pending] = []
    private var retryTasks: [String: Task<Void, Never>] = [:]
    private let logger: SDKLoggerProtocol?

    init(logger: SDKLoggerProtocol? = nil) {
        self.logger = logger
    }

    /// Enqueues a payment for processing. Starts immediately if idle.
    /// Duplicate ids (already processing, already pending, or backing off) are ignored — the store
    /// republishes a backing-off row on every save, and that must not short-circuit its delay.
    func scheduleIfNeeded(
        paymentId: String,
        onExecute: @escaping @Sendable () -> Task<Void, Never>
    ) {
        guard paymentId != currentPaymentId,
              retryTasks[paymentId] == nil,
              !pendingTasks.contains(where: { $0.paymentId == paymentId })
        else {
            return
        }

        if currentPaymentId == nil {
            startProcessing(Pending(paymentId: paymentId, onExecute: onExecute))
        } else {
            pendingTasks.append(Pending(paymentId: paymentId, onExecute: onExecute))
            logger?.debug("Queued payment \(paymentId), pending: \(pendingTasks.count)")
        }
    }

    /// Called when payment execution finishes. Starts the next pending payment.
    func onComplete(paymentId: String) {
        guard currentPaymentId == paymentId else { return }

        currentTask = nil
        currentPaymentId = nil

        startNextPendingIfNeeded()
    }

    /// Re-enters `paymentId` through the normal queue after `delay`, without holding the processing
    /// slot meanwhile — other payments keep flowing while this one backs off. Ignored while a retry
    /// for the same id is already pending.
    func scheduleRetry(
        paymentId: String,
        after delay: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        onExecute: @escaping @Sendable () -> Task<Void, Never>
    ) {
        guard retryTasks[paymentId] == nil else { return }

        retryTasks[paymentId] = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }

            await self?.retryElapsed(paymentId: paymentId, onExecute: onExecute)
        }
        logger?.debug("Retry of payment \(paymentId) in \(delay)s")
    }

    func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
        currentPaymentId = nil
        pendingTasks.removeAll()
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
    }
}

// MARK: - Private

private extension ExternalPaymentContext {
    func startProcessing(_ pending: Pending) {
        currentPaymentId = pending.paymentId
        currentTask = pending.onExecute()
        logger?.debug("Started processing payment \(pending.paymentId)")
    }

    func retryElapsed(paymentId: String, onExecute: @escaping @Sendable () -> Task<Void, Never>) {
        guard retryTasks.removeValue(forKey: paymentId) != nil else { return }
        scheduleIfNeeded(paymentId: paymentId, onExecute: onExecute)
    }

    func startNextPendingIfNeeded() {
        guard !pendingTasks.isEmpty else { return }

        let next = pendingTasks.removeFirst()
        startProcessing(next)
    }
}
