import AsyncExtensions
import Coinage
import CommonService
import Foundation
import Keystore_iOS

// MARK: - State

enum CoinageRecoveryState: Equatable {
    case idle
    case inProgress
    case completed
}

// MARK: - Protocol

protocol CoinageBackupSyncServicing: AsyncApplicationServicing {
    /// The recovery state derived from Coinage's ``BackupProgress``. Replays the last state.
    var stateStream: AnyAsyncSequence<CoinageRecoveryState> { get }

    /// Another look for balance under previous installations.
    func triggerRecovery()

    /// The user accepted the recovered balance: the card closes and stays closed until a later scan
    /// finds a new installation.
    func acknowledgeRecovery()
}

// MARK: - Implementation

/// Bridges Coinage's backup progress to the wallet: mirrors it into the persisted "restore pending"
/// flag the Asset Details card reads, and forwards the card's actions.
final class CoinageBackupSyncService: CoinageBackupSyncServicing, @unchecked Sendable {
    private let coinageService: any CoinageServicing
    private let balanceSyncStateStorage: BalanceSyncStateStoring
    private let logger: LoggerProtocol

    private let stateSubject = AsyncCurrentValueSubject<CoinageRecoveryState>(.idle)
    private var progressTask: Task<Void, Never>?

    var stateStream: AnyAsyncSequence<CoinageRecoveryState> {
        stateSubject.eraseToAnyAsyncSequence()
    }

    init(
        coinageService: any CoinageServicing,
        balanceSyncStateStorage: BalanceSyncStateStoring = BalanceSyncStateStorage(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.coinageService = coinageService
        self.balanceSyncStateStorage = balanceSyncStateStorage
        self.logger = logger
    }

    func setup() async {
        progressTask?.cancel()
        progressTask = Task { [weak self, coinageService, logger] in
            do {
                for try await progress in coinageService.subscribeBackupProgress() {
                    self?.apply(progress)
                }
            } catch {
                logger.error("Coinage backup progress stream failed: \(error)")
            }
        }
    }

    func throttle() async {
        progressTask?.cancel()
        progressTask = nil
    }

    func triggerRecovery() {
        Task { [coinageService] in
            await coinageService.deepSearchBackup()
        }
    }

    func acknowledgeRecovery() {
        Task { [coinageService] in
            await coinageService.markBackupAsCompleted()
        }
    }
}

private extension CoinageBackupSyncService {
    func apply(_ progress: BackupProgress) {
        logger.debug("Coinage backup progress: \(progress)")

        let restorePending = progress.awaitsAcknowledgement
        if balanceSyncStateStorage.isRestorePending != restorePending {
            balanceSyncStateStorage.isRestorePending = restorePending
        }

        stateSubject.send(progress.isInProgress ? .inProgress : (restorePending ? .completed : .idle))
    }
}

// MARK: - Acknowledgement flag

/// The persisted "user accepted the recovered balance" flag Coinage resets when a scan finds more.
final class CoinageDeepRecoveryCompletedStore: DeepRecoveryCompletedStoring, @unchecked Sendable {
    private let settingsManager: SettingsManagerProtocol

    init(settingsManager: SettingsManagerProtocol = SettingsManager.shared) {
        self.settingsManager = settingsManager
    }

    func isDeepRecoveryCompleted() async -> Bool {
        settingsManager.value(for: .coinageDeepRecoveryCompleted)
    }

    func setDeepRecoveryCompleted(_ completed: Bool) async {
        settingsManager.set(value: completed, for: .coinageDeepRecoveryCompleted)
    }
}
