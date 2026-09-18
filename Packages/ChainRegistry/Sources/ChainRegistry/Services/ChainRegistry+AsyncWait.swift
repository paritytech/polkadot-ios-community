import Foundation
import Operation_iOS
import OperationExt
import os

public extension ChainRegistryProtocol {
    func asyncChains(
        for chainIDs: Set<ChainModel.Id>,
        workQueue: DispatchQueue = .global()
    ) -> CompoundOperationWrapper<[ChainModel.Id: ChainModel]> {
        let subscriptionId = NSObject()

        let operation = AsyncClosureOperation<[ChainModel.Id: ChainModel]>(operationClosure: { [weak self] closure in
            self?.chainsSubscribe(
                subscriptionId,
                runningInQueue: workQueue
            ) { changes in
                guard !changes.isEmpty else {
                    return
                }

                self?.chainsUnsubscribe(subscriptionId)
                let allChains = changes.allChangedItems()

                let chainIDsWithChainModel = allChains.filter { chainIDs.contains($0.chainId) }
                    .reduce(into: [ChainModel.Id: ChainModel]()) {
                        $0[$1.chainId] = $1
                    }
                closure(.success(chainIDsWithChainModel))
            }
        }, cancelationClosure: { [weak self] in
            self?.chainsUnsubscribe(subscriptionId)
        })

        return CompoundOperationWrapper(targetOperation: operation)
    }

    func asyncWaitChainsSetup(for chainIds: Set<ChainModel.Id>) async {
        guard !chainIds.isEmpty else { return }

        let syncQueue = DispatchQueue(label: "io.chain.registry.wait.chain.setup")
        let waiter = ChainsSetupWaiter()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiter.start(
                    chainIds: chainIds,
                    registry: self,
                    guardian: ContinuationGuard(continuation),
                    syncQueue: syncQueue
                )
            }
        } onCancel: {
            waiter.cancel()
        }
    }
}

private final class ChainsSetupWaiter: @unchecked Sendable {
    private struct ActiveSubscription {
        let target: NSObject
        let registry: ChainRegistryProtocol
        let guardian: ContinuationGuard
    }

    private enum WaiterState {
        case initial
        case active(
            target: NSObject,
            availableChains: [ChainModel.Id: ChainModel],
            guardian: ContinuationGuard,
            registry: ChainRegistryProtocol
        )
        case done
    }

    private let stateLock = OSAllocatedUnfairLock<WaiterState>(initialState: .initial)

    func start(
        chainIds: Set<ChainModel.Id>,
        registry: ChainRegistryProtocol,
        guardian: ContinuationGuard,
        syncQueue: DispatchQueue
    ) {
        let target = NSObject()

        let shouldSubscribe = stateLock.withLock { state -> Bool in
            switch state {
            case .initial:
                state = .active(target: target, availableChains: [:], guardian: guardian, registry: registry)
                return true
            case .active,
                 .done:
                return false
            }
        }

        guard shouldSubscribe else {
            // Already cancelled before we could subscribe
            guardian.resume()
            return
        }

        registry.chainsSubscribe(target, runningInQueue: syncQueue) { [weak self] changes in
            guard let self else { return }

            if apply(changes, requiring: chainIds) {
                finish()
            }
        }
    }

    func cancel() {
        finish()
    }
}

private extension ChainsSetupWaiter {
    /// Folds the changes into the active state and reports whether every required chain is now available.
    func apply(_ changes: [DataProviderChange<ChainModel>], requiring chainIds: Set<ChainModel.Id>) -> Bool {
        stateLock.withLock { state -> Bool in
            guard case let .active(target, availableChains, guardian, registry) = state else {
                return false
            }

            var updatedChains = availableChains

            for change in changes {
                switch change {
                case let .insert(chain),
                     let .update(chain):
                    updatedChains[chain.chainId] = chain
                case let .delete(chainId):
                    updatedChains[chainId] = nil
                }
            }

            state = .active(
                target: target,
                availableChains: updatedChains,
                guardian: guardian,
                registry: registry
            )

            return chainIds.allSatisfy { updatedChains[$0] != nil }
        }
    }

    /// Single exit point for both completion and cancellation: the state read and the `.done`
    /// transition share one lock acquisition, so unsubscribe and resume happen at most once.
    func finish() {
        let subscription = stateLock.withLock { state -> ActiveSubscription? in
            defer { state = .done }

            guard case let .active(target, _, guardian, registry) = state else {
                return nil
            }

            return ActiveSubscription(target: target, registry: registry, guardian: guardian)
        }

        guard let subscription else { return }

        subscription.registry.chainsUnsubscribe(subscription.target)
        subscription.guardian.resume()
    }
}

private final class ContinuationGuard: Sendable {
    private let hasResumedLock = OSAllocatedUnfairLock(initialState: false)
    private let continuation: CheckedContinuation<Void, Never>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        let shouldResume = hasResumedLock.withLock { hasResumed in
            guard !hasResumed else { return false }

            hasResumed = true

            return true
        }

        if shouldResume {
            continuation.resume()
        }
    }
}
