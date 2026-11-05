import Foundation
import KeyDerivation

extension ServiceCoordinator {
    static func createActiveInstallationService(logger: LoggerProtocol) -> ActiveInstallationServicing {
        ActiveInstallationServiceFactory(statusStore: InstallationStatusStore(logger: logger), logger: logger)
            .makeService()
    }

    /// Follows transfer requests only while this phone is active, which the installation service decides.
    static func createDeviceTransferRequestListener(
        installationObserver: CurrentInstallationObserving,
        logger: LoggerProtocol
    ) -> DeviceTransferRequestListening {
        DeviceTransferRequestListener(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(entropyManager: RootEntropyManager.shared),
            processedStore: DeviceTransferProcessedCoreDataStore(storageFacade: UserDataStorageFacade.shared),
            installationObserver: installationObserver,
            logger: logger
        )
    }

    func setupDeviceTransferServices() async {
        do {
            let configuration = try ActiveInstallationServiceFactory(
                statusStore: InstallationStatusStore(logger: logger),
                logger: logger
            ).makeConfiguration()
            await activeInstallationService.setup(configuration: configuration)
            await deviceTransferRequestListener.setup(connection: configuration.connection)
        } catch {
            logger.error("Failed to set up device transfer services: \(error)")
        }
    }
}
