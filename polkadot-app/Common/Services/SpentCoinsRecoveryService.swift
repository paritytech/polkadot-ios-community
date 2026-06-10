import AsyncExtensions
import Coinage
import CommonService
import Foundation
import BigInt

// MARK: - State

enum SpentCoinsRecoveryState: Equatable {
    case idle
    case inProgress
    case completed(BigUInt)
    case failed(String)
}

// MARK: - Protocol

protocol SpentCoinsRecoveryServicing: AsyncApplicationServicing {
    /// Current recovery state stream. Replays last state to new subscribers.
    var stateStream: AnyAsyncSequence<SpentCoinsRecoveryState> { get }

    /// Triggers a new recovery, cancelling any in-flight recovery.
    func triggerRecovery()
}

// MARK: - Implementation

final class SpentCoinsRecoveryService: SpentCoinsRecoveryServicing, @unchecked Sendable {
    private let coinageService: any CoinageServicing

    private let stateSubject = AsyncCurrentValueSubject<SpentCoinsRecoveryState>(.idle)
    private var recoveryTask: Task<Void, Never>?

    var stateStream: AnyAsyncSequence<SpentCoinsRecoveryState> {
        stateSubject.eraseToAnyAsyncSequence()
    }

    init(coinageService: any CoinageServicing) {
        self.coinageService = coinageService
    }

    func setup() async {
        // No-op: recovery only starts when user taps Recover button
    }

    func throttle() async {
        recoveryTask?.cancel()
        recoveryTask = nil
        stateSubject.send(.idle)
    }

    func triggerRecovery() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            await self?.performRecovery()
        }
        stateSubject.send(.inProgress)
    }
}

// MARK: - Recovery logic

private extension SpentCoinsRecoveryService {
    func performRecovery() async {
        guard !Task.isCancelled else { return }

        do {
            let total = try await coinageService.recoverSpentCoinsOnChain()
            guard !Task.isCancelled else { return }
            stateSubject.send(.completed(total))
        } catch {
            guard !Task.isCancelled else { return }
            stateSubject.send(.failed(error.localizedDescription))
        }
    }
}
