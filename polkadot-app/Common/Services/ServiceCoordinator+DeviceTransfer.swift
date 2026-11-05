import Foundation

extension ServiceCoordinator {
    static func createActiveInstallationService(logger: LoggerProtocol) -> ActiveInstallationServicing {
        ActiveInstallationServiceFactory(statusStore: InstallationStatusStore(logger: logger), logger: logger)
            .makeService()
    }

    func setupActiveInstallationService() async {
        do {
            let configuration = try ActiveInstallationServiceFactory(
                statusStore: InstallationStatusStore(logger: logger),
                logger: logger
            ).makeConfiguration()
            await activeInstallationService.setup(configuration: configuration)
        } catch {
            logger.error("Failed to set up active installation tracking: \(error)")
        }
    }
}
