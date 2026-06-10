import UIKit
import Operation_iOS
import Foundation_iOS
import Coinage
import SDKLogger
import BigInt
import AsyncExtensions

final class RecoverPendingTransactionsInteractor {
    weak var presenter: RecoverPendingTransactionsInteractorOutputProtocol?

    private let spentCoinsRecoveryService: any SpentCoinsRecoveryServicing
    private let minimumInProgressDuration: Duration
    private var subscriptionTask: Task<Void, Never>?
    private var inProgressStartedAt: ContinuousClock.Instant?

    init(
        spentCoinsRecoveryService: any SpentCoinsRecoveryServicing,
        minimumInProgressDuration: Duration = .milliseconds(500)
    ) {
        self.spentCoinsRecoveryService = spentCoinsRecoveryService
        self.minimumInProgressDuration = minimumInProgressDuration
    }

    deinit {
        subscriptionTask?.cancel()
    }
}

extension RecoverPendingTransactionsInteractor: RecoverPendingTransactionsInteractorInputProtocol {
    func setup() {
        subscriptionTask = Task { [weak self] in
            guard let stream = self?.spentCoinsRecoveryService.stateStream else { return }
            do {
                for try await state in stream {
                    await self?.forward(state)
                }
            } catch {
                // Ignore stream errors (e.g., cancellation)
            }
        }
    }

    private func forward(_ state: SpentCoinsRecoveryState) async {
        switch state {
        case .inProgress:
            inProgressStartedAt = ContinuousClock.now
            await presenter?.didUpdateState(state)
        case .idle,
             .completed,
             .failed:
            if let startedAt = inProgressStartedAt {
                let elapsed = ContinuousClock.now - startedAt
                let remaining = minimumInProgressDuration - elapsed
                if remaining > .zero {
                    try? await Task.sleep(for: remaining)
                }
                inProgressStartedAt = nil
            }
            await presenter?.didUpdateState(state)
        }
    }

    func recover() {
        spentCoinsRecoveryService.triggerRecovery()
    }
}
