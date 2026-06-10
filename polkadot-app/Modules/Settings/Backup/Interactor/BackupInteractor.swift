import UIKit
import Keystore_iOS
import KeyDerivation

final class BackupInteractor {
    // MARK: Properties

    weak var presenter: BackupInteractorOutputProtocol?
    private let cloudKeychain: SynchronizableKeychain
    private let entropyManager: RootEntropyManaging
    private let logger: LoggerProtocol
    private let eventCenter: EventCenterProtocol
    private let backupTag = SynchronizableKeychainTag.walletEntropy

    // MARK: Initial methods

    init(
        cloudKeychain: SynchronizableKeychain,
        entropyManager: RootEntropyManaging,
        logger: LoggerProtocol,
        eventCenter: EventCenterProtocol = EventCenter.shared
    ) {
        self.cloudKeychain = cloudKeychain
        self.entropyManager = entropyManager
        self.logger = logger
        self.eventCenter = eventCenter
    }

    // MARK: Private methods

    private func checkBackup() throws -> Bool {
        try cloudKeychain.checkKey(for: backupTag)
    }
}

// MARK: - BackupInteractorInputProtocol

extension BackupInteractor: BackupInteractorInputProtocol {
    func checkBackupStatus() {
        let icloudIsAvailable = cloudKeychain.isAvailable
        if !icloudIsAvailable {
            presenter?.didReceiveBackupStatus(.cloudIsOff)
        } else {
            do {
                let hasBackup = try checkBackup()
                presenter?.didReceiveBackupStatus(hasBackup ? .created : .notFound)
            } catch {
                logger.debug(error.localizedDescription)
                presenter?.didReceiveBackupStatus(.cloudIsOff)
            }
        }
    }

    func backupMnemonic() {
        do {
            let entropy = try entropyManager.fetchRootEntropy()
            try cloudKeychain.addKey(entropy, with: backupTag)
            if try checkBackup() {
                presenter?.didReceiveBackupComplete(with: .success(()))
                eventCenter.notify(with: BackupStatusChanged())
            } else {
                presenter?.didReceiveBackupComplete(with: .failure(BackupInteractorError.failedCreateBackup))
            }
        } catch {
            presenter?.didReceiveBackupComplete(with: .failure(error))
        }
    }
}
