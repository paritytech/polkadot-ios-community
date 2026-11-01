import Foundation

protocol DashboardServicesResetting: AnyObject {
    @MainActor func reset()
}

extension DashboardServicesManager: DashboardServicesResetting {}

enum DashboardServices {
    static let flowStateProvider: SPAFlowStateProviding = SPAFlowStateProvider()

    @MainActor static let manager = DashboardServicesManager<ServiceCoordinator>(
        bootstrapper: BackgroundTaskBootstrapper.makeDefault(),
        coordinatorFactory: ServiceCoordinatorFactory(flowStateProvider: flowStateProvider),
        connectionRetention: ChainRegistryConnectionRetention(),
        headlessBootDeadline: .seconds(20),
        logger: Logger.shared
    )
}

struct ServiceCoordinatorFactory: DashboardServicesCoordinatorMaking {
    let flowStateProvider: SPAFlowStateProviding

    @MainActor
    func makeCoordinator() -> ServiceCoordinator? {
        ServiceCoordinator.createDefault(spaFlowState: flowStateProvider.flowState())
    }
}
