import Foundation
@preconcurrency import SubstrateSdk
@preconcurrency import SubstrateOperation
import StructuredConcurrency
@preconcurrency import SDKLogger
@preconcurrency import AsyncExtensions
import AsyncAlgorithms

/// Runs a recovery pass on every new finalized head.
///
/// This is the trigger `RecoveryPass` documents but never had: a submission's watcher releases
/// its entry at `.inBlock`, strictly before finality, so without a head-driven pass an entry
/// that executed successfully is never re-evaluated and its outputs stay `pendingMint`.
final class FinalizedHeadTrigger: Sendable {
    private let blockInfoProvider: any BlockInfoProviding
    private let onHead: @Sendable () async -> Void
    private let logger: SDKLoggerProtocol?

    /// Reconnect attempts before the trigger gives up and waits for the next `start()`.
    private static let maxSubscribeAttempts = 5

    init(
        blockInfoProvider: any BlockInfoProviding,
        onHead: @escaping @Sendable () async -> Void,
        logger: SDKLoggerProtocol?
    ) {
        self.blockInfoProvider = blockInfoProvider
        self.onHead = onHead
        self.logger = logger
    }

    func run() async {
        while !Task.isCancelled {
            do {
                // Wrap retry/resubscribe in stall activity so a persistent connection failure
                // is visible. The activity ends the moment the first head arrives.
                let heads = try await markStallActivity("Reconnecting to chain") { [blockInfoProvider] in
                    try await withRetry(
                        maxAttempts: Self.maxSubscribeAttempts,
                        initialDelay: .seconds(1)
                    ) { [blockInfoProvider] in
                        let sequence = blockInfoProvider.subscribeFinalizedHeads()
                        var iterator = sequence.makeAsyncIterator()
                        guard let firstHead = try await iterator.next() else {
                            throw FinalizedHeadTriggerError.subscriptionEndedBeforeFirstHead
                        }

                        // Yield first element plus rest, deduped within this subscription
                        // to guard against the same head being yielded twice on one connection.
                        return PrefixedHeadSequence(firstElement: firstHead, iterator: iterator)
                            .removeDuplicates { $0.number == $1.number }
                            .eraseToAnyAsyncSequence()
                    }
                }

                for try await _ in heads {
                    guard !Task.isCancelled else { return }
                    // Every head runs a full pass. A cheap `hasLiveEntries()` check on
                    // `CoinageTxRepositoryProtocol` belongs here — not in `RecoveryPass.run()`, because
                    // `performPass` opens with `reconciler.reconcile()`, which repairs coin/voucher
                    // projection drift and must keep running for the other four call sites. A
                    // CoreData predicate count on `CDDurabilityEntry.status IN {0,1}` would do it;
                    // `fetchLive()` today is a full-table read and entries are never deleted.
                    await onHead()
                }
            } catch RetryError.limitReached {
                logger?.error("Finalized head subscription exhausted retries, pausing")
                return
            } catch {
                logger?.error("Finalized head subscription failed: \(error), reconnecting")
            }
        }
    }
}

// MARK: - Private Error

private enum FinalizedHeadTriggerError: Error {
    /// The subscription ended before yielding any head.
    case subscriptionEndedBeforeFirstHead
}

// MARK: - Async Sequence Wrapper

/// Wraps an iterator to re-yield its first element plus all subsequent elements.
///
/// Declared `@unchecked Sendable` because `AnyAsyncIterator<Block.Header>` is not `Sendable`
/// (its element type `Block.Header` from SubstrateSdk is not). The iterator is consumed within
/// a single uncontended async task spawned by `withRetry`; no concurrent access occurs.
private struct PrefixedHeadSequence: AsyncSequence, @unchecked Sendable {
    typealias Element = Block.Header

    let firstElement: Block.Header
    var iterator: AnyAsyncIterator<Block.Header>

    func makeAsyncIterator() -> Iterator {
        Iterator(
            firstElement: firstElement,
            iterator: iterator,
            yieldedFirst: false
        )
    }

    struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
        typealias Element = Block.Header

        let firstElement: Block.Header
        var iterator: AnyAsyncIterator<Block.Header>
        var yieldedFirst: Bool

        mutating func next() async throws -> Block.Header? {
            if !yieldedFirst {
                yieldedFirst = true
                return firstElement
            }
            return try await iterator.next()
        }
    }
}
