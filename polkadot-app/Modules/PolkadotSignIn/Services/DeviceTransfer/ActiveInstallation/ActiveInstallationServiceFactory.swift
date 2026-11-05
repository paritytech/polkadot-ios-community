import Foundation
import StatementStore
import ChainRegistry
import KeyDerivation

protocol ActiveInstallationServiceMaking {
    func makeService() -> ActiveInstallationServicing
    func makeConfiguration() throws -> ActiveInstallationConfiguration
}

/// Every screen that follows the active installation record builds its own service; only one of them is on screen
/// at a time, and all of them save to the same store.
struct ActiveInstallationServiceFactory {
    let statusStore: InstallationStatusStoring
    let logger: LoggerProtocol
}

extension ActiveInstallationServiceFactory: ActiveInstallationServiceMaking {
    func makeService() -> ActiveInstallationServicing {
        ActiveInstallationService(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(entropyManager: RootEntropyManager.shared),
            installationProvider: CoinageCurrentInstallationProvider(
                repository: CoinageCurrentInstallationCoreDataRepository(storageFacade: UserDataStorageFacade.shared)
            ),
            publishSettings: ActiveInstallationPublishSettings(deviceInfo: .current()),
            statusStore: statusStore,
            logger: logger
        )
    }

    func makeConfiguration() throws -> ActiveInstallationConfiguration {
        let connection = try ChainRegistryFacade.sharedRegistry.getConnectionOrError(for: AppConfig.Chains.chatChain)
        let statementsConnection = StatementStoreConnection(
            connection: connection,
            retryMatcher: StatementSubmitErrorMatcher.retryWhenTimeoutOrNoAllowance(),
            logger: logger
        )
        let signer = try ChatSignerManager().makeSigner(for: Chat.Contact.Own.main().signKeyId)

        return ActiveInstallationConfiguration(connection: statementsConnection, signer: signer)
    }
}
