import Foundation
import AsyncExtensions
import BigInt
import ChainRegistry
import Operation_iOS
import SubstrateOperation
import SubstrateSdk

struct ChainBlockInfo: Equatable {
    let number: BlockNumber
    let receivedAt: Date
}

@MainActor
protocol ChainBlockProviding: AnyObject {
    func blockStream() -> AnyAsyncSequence<[ChainConnectionTarget: ChainBlockInfo]>
    func setActive(_ isActive: Bool)
}

/// Per-chain best block height, subscribed only while a host asks for it.
///
/// Sibling to `ChainStatusProvider` rather than part of it: this owns head subscriptions only, so
/// row composition stays in one place.
@MainActor
final class ChainBlockProvider {
    private let blocksSubject = AsyncCurrentValueSubject<[ChainConnectionTarget: ChainBlockInfo]>([:])

    private let blockProviders: [ChainConnectionTarget: BlockInfoProviding]
    private let logger: LoggerProtocol

    private var blocks: [ChainConnectionTarget: ChainBlockInfo] = [:]
    private var subscriptionTasks: [Task<Void, Never>] = []
    private var isActive = false

    init(
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.logger = logger

        blockProviders = ChainConnectionTarget.allCases
            .reduce(into: [ChainConnectionTarget: BlockInfoProviding]()) { accumulator, target in
                accumulator[target] = BlockInfoProvider(
                    chainRegistry: chainRegistry,
                    operationQueue: operationQueue,
                    chainId: target.chainId
                )
            }
    }

    deinit {
        subscriptionTasks.forEach { $0.cancel() }
    }
}

extension ChainBlockProvider: ChainBlockProviding {
    func blockStream() -> AnyAsyncSequence<[ChainConnectionTarget: ChainBlockInfo]> {
        blocksSubject.eraseToAnyAsyncSequence()
    }

    func setActive(_ isActive: Bool) {
        guard isActive != self.isActive else {
            return
        }

        self.isActive = isActive

        guard isActive else {
            // Values are kept so reopening shows the last known heights instead of blanking;
            // stale entries are dropped by status transitions, not by deactivation.
            subscriptionTasks.forEach { $0.cancel() }
            subscriptionTasks = []
            return
        }

        subscriptionTasks = blockProviders.flatMap { target, provider in
            [fetchCurrent(for: target, using: provider), observeHeads(for: target, using: provider)]
        }
    }
}

private extension ChainBlockProvider {
    /// Heights would otherwise stay blank for up to a full block time after activation.
    func fetchCurrent(
        for target: ChainConnectionTarget,
        using provider: BlockInfoProviding
    ) -> Task<Void, Never> {
        Task { [weak self, logger] in
            do {
                let number = try await provider.fetchCurrent()
                self?.record(number, for: target)
            } catch {
                logger.error("Block number fetch failed for \(target.chainId): \(error)")
            }
        }
    }

    func observeHeads(
        for target: ChainConnectionTarget,
        using provider: BlockInfoProviding
    ) -> Task<Void, Never> {
        Task { [weak self, logger] in
            do {
                for try await header in provider.subscribeNewHeads() {
                    guard let number = BigUInt.fromHexString(header.number) else {
                        logger.warning("Unparsable block number for \(target.chainId): \(header.number)")
                        continue
                    }

                    self?.record(BlockNumber(number), for: target)
                }
            } catch {
                logger.error("New heads stream failed for \(target.chainId): \(error)")
            }
        }
    }

    func record(_ number: BlockNumber, for target: ChainConnectionTarget) {
        blocks[target] = ChainBlockInfo(number: number, receivedAt: Date())
        blocksSubject.send(blocks)
    }
}
