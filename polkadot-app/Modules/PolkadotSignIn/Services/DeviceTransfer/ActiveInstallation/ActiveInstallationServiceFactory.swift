import Foundation
import StatementStore
import ChainRegistry
import KeyDerivation
import IssueMonitoring

protocol ActiveInstallationServiceMaking {
    func makeService() -> ActiveInstallationServicing
    func makeConfiguration() throws -> ActiveInstallationConfiguration
}

/// Every screen that follows the active installation record builds its own service; only one of them is on screen
/// at a time, and all of them save to the same store.
struct ActiveInstallationServiceFactory {
    let statusStore: InstallationStatusStoring
    let logger: LoggerProtocol
    var stopDiagnostic: IssueDiagnostic = DeviceTransferIssueDiagnostics.makeDefault().installationStopped
}

extension ActiveInstallationServiceFactory: ActiveInstallationServiceMaking {
    func makeService() -> ActiveInstallationServicing {
        var publishSettings = ActiveInstallationPublishSettings(deviceInfo: .current())
        publishSettings.stopDiagnostic = stopDiagnostic

        return ActiveInstallationService(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(entropyManager: RootEntropyManager.shared),
            installationProvider: CoinageCurrentInstallationProvider(
                repository: CoinageCurrentInstallationCoreDataRepository(storageFacade: UserDataStorageFacade.shared)
            ),
            publishSettings: publishSettings,
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
