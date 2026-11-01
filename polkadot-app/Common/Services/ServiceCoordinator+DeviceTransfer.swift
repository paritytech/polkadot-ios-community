import Foundation

extension ServiceCoordinator {
    static func createActiveInstallationService(logger: LoggerProtocol) -> ActiveInstallationServicing {
        ActiveInstallationServiceFactory(logger: logger).makeService()
    }

    func setupActiveInstallationService() async {
        do {
            let configuration = try ActiveInstallationServiceFactory(logger: logger).makeConfiguration()
            await activeInstallationService.setup(configuration: configuration)
        } catch {
            logger.error("Failed to set up active installation tracking: \(error)")
        }
    }
}
