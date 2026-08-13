import Foundation
import Foundation_iOS
import Operation_iOS
import SubstrateSdk
import SDKLogger

public typealias StatementHandlingStatus = Bool
public typealias StatementHandlingClosure = (Statement) -> StatementHandlingStatus

public protocol StatementSubscribing {
    func start(handler: @escaping StatementHandlingClosure)
    func stop()
    func fetchOnce(
        handler: @escaping StatementHandlingClosure,
        completion: ((StatementSubscriptionError?) -> Void)?
    )
    func resetSeenHashes()
}

// Mutable state is confined to workQueue. The conformance is unchecked because
// Task/DispatchQueue boundaries cannot express that invariant to the compiler.
public final class StatementSubscription: @unchecked Sendable {
    private let connection: StatementStoreFetching
    private let topicFilter: TopicFilter
    private let proofVerifier: StatementStoreProofVerifying
    private let workQueue: DispatchQueue
    private let logger: SDKLoggerProtocol?

    private var subscriptionTask: Task<Void, Never>?
    private var seenHashes = Set<Data>()

    public init(
        connection: StatementStoreFetching,
        topicFilter: TopicFilter,
        proofVerifier: StatementStoreProofVerifying,
        workQueue: DispatchQueue,
        logger: SDKLoggerProtocol?
    ) {
        self.connection = connection
        self.topicFilter = topicFilter
        self.proofVerifier = proofVerifier
        self.workQueue = workQueue
        self.logger = logger
    }

    deinit {
        subscriptionTask?.cancel()
    }
}

extension StatementSubscription: StatementSubscribing {
    public func start(handler: @escaping StatementHandlingClosure) {
        workQueue.async { [weak self] in
            self?.performStop()
            self?.performSubscription(handler: handler)
        }
    }

    public func stop() {
        workQueue.async { [weak self] in
            self?.performStop()
        }
    }

    public func resetSeenHashes() {
        workQueue.async { [weak self] in
            self?.seenHashes = []
        }
    }

    public func fetchOnce(
        handler: @escaping StatementHandlingClosure,
        completion: ((StatementSubscriptionError?) -> Void)?
    ) {
        Task { [connection, topicFilter, workQueue, logger, weak self] in
            logger?.debug("Going to fetch events")

            do {
                let dataList = try await connection.fetchStatements(
                    with: topicFilter
                )
                workQueue.async {
                    let error = self?.handleData(dataList, with: handler)
                    completion?(error)
                }
            } catch {
                logger?.error("Failed to fetch data: \(error)")
                workQueue.async {
                    completion?(.other(error))
                }
            }
        }
    }
}

private extension StatementSubscription {
    func performSubscription(handler: @escaping StatementHandlingClosure) {
        subscriptionTask = Task { [connection, topicFilter, logger, weak self] in
            do {
                let stream = try connection.subscribeStatements(with: topicFilter)

                for try await page in stream {
                    guard let self else { return }
                    _ = await handleDataOnWorkQueue(page.statements, with: handler)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                logger?.error("Subscription failed: \(error)")
            }
        }
    }

    func performStop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    func handleDataOnWorkQueue(
        _ dataList: [Data],
        with handler: @escaping StatementHandlingClosure
    ) async -> StatementSubscriptionError? {
        await withCheckedContinuation { continuation in
            workQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let error = handleData(dataList, with: handler)
                continuation.resume(returning: error)
            }
        }
    }

    func handleData(
        _ dataList: [Data],
        with handler: @escaping StatementHandlingClosure
    ) -> StatementSubscriptionError? {
        var subscriptionError: StatementSubscriptionError?

        for data in dataList {
            guard
                let hash = makeHash(data: data),
                !seenHashes.contains(hash)
            else {
                continue
            }

            guard let statement = decodeStatement(from: data) else {
                // mark failed to decode statement as seen
                subscriptionError = .statementDecodingFailed
                seenHashes.insert(hash)
                continue
            }

            guard proofVerifier.verifyProof(for: statement) else {
                logger?.error("Proof verification failed")
                seenHashes.insert(hash)
                continue
            }

            guard handler(statement) else {
                continue
            }

            seenHashes.insert(hash)
        }

        return subscriptionError
    }

    func makeHash(data: Data) -> Data? {
        do {
            return try data.blake2b32()
        } catch {
            logger?.error("Failed to make hash: \(error.localizedDescription)")
            return nil
        }
    }

    func decodeStatement(from data: Data) -> Statement? {
        do {
            let decoder = try ScaleDecoder(data: data)
            return try Statement(scaleDecoder: decoder)
        } catch {
            logger?.error("Failed to decode statement data: \(error.localizedDescription)")
            return nil
        }
    }
}
