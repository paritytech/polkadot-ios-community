import Foundation
import StatementStore
import ChainRegistry
import KeyDerivation

extension ServiceCoordinator {
    static func createActiveInstallationService(logger: LoggerProtocol) -> ActiveInstallationServicing {
        ActiveInstallationService(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(entropyManager: RootEntropyManager.shared),
            installationProvider: CoinageCurrentInstallationProvider(
                repository: CoinageCurrentInstallationCoreDataRepository(storageFacade: UserDataStorageFacade.shared)
            ),
            deviceInfo: .current(),
            logger: logger
        )
    }

    func setupActiveInstallationService() async {
        do {
            let connection = try ChainRegistryFacade.sharedRegistry.getConnectionOrError(
                for: AppConfig.Chains.chatChain
            )
            let statementsConnection = StatementStoreConnection(
                connection: connection,
                retryMatcher: StatementSubmitErrorMatcher.retryWhenTimeoutOrNoAllowance(),
                logger: logger
            )
            let signer = try ChatSignerManager().makeSigner(for: Chat.Contact.Own.main().signKeyId)

            await activeInstallationService.setup(
                configuration: ActiveInstallationConfiguration(connection: statementsConnection, signer: signer)
            )
        } catch {
            logger.error("Failed to set up active installation tracking: \(error)")
        }
    }
}
