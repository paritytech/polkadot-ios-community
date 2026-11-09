import ChainRegistry
import Foundation
import FoundationExt

protocol DashboardServicesCoordinatorMaking<Coordinator> {
    associatedtype Coordinator: DashboardServicesCoordinating

    @MainActor func makeCoordinator() -> Coordinator?
}

struct DashboardServicesHeadlessBoot {
    let bootstrapper: BackgroundTaskBootstrapping
    let deadline: Duration
}

/// Once no lease is left the coordinator is stopped and dropped, so a stopped instance is never started again.
/// While the app is in the background the interactive part waits for the foreground or an explicit request:
/// a background task launch also connects the scene, and its dashboard must not start chat or a second renewal.
@MainActor
final class DashboardServicesManager<Coordinator: DashboardServicesCoordinating> {
    private let headlessBootConfig: DashboardServicesHeadlessBoot
    private let coordinatorFactory: any DashboardServicesCoordinatorMaking<Coordinator>
    private let connectionRetention: BackgroundConnectionRetaining
    private let activity: any ApplicationActivityProviding
    private let logger: LoggerProtocol

    private var coordinator: Coordinator?
    private var generation: UInt64 = 0
    private var leaseCounts: [DashboardServicesDemand: Int] = [:]
    private var headlessBoot: Task<Coordinator?, Never>?
    private var pendingInteractiveStart: Task<Void, Never>?
    private var isInteractiveRequested = false
    private var isInteractiveStarted = false

    init(
        headlessBoot: DashboardServicesHeadlessBoot,
        coordinatorFactory: any DashboardServicesCoordinatorMaking<Coordinator>,
        connectionRetention: BackgroundConnectionRetaining,
        activity: any ApplicationActivityProviding,
        logger: LoggerProtocol
    ) {
        headlessBootConfig = headlessBoot
        self.coordinatorFactory = coordinatorFactory
        self.connectionRetention = connectionRetention
        self.activity = activity
        self.logger = logger
    }

    var isInteractiveRunning: Bool {
        isInteractiveStarted
    }

    func acquireInteractive() -> DashboardServicesLease<Coordinator>? {
        guard let coordinator = existingOrNewCoordinator() else { return nil }

        let isFirstInteractiveLease = leaseCount(for: .interactive) == 0
        let lease = makeLease(.interactive, for: coordinator, connectionToken: nil)

        if isFirstInteractiveLease {
            startInteractiveWhenNeeded(coordinator)
        }

        return lease
    }

    /// An incoming call needs chat signalling even while the app stays in the background.
    func requestInteractiveStart() {
        isInteractiveRequested = true
        openInteractiveGate(generation: generation)
    }

    func acquireDurability() async -> DashboardServicesLease<Coordinator>? {
        guard let coordinator = await existingOrHeadlessCoordinator() else { return nil }

        // After the boot: reaching the registry opens the chain store, which migrations must precede.
        let connectionToken = connectionRetention.retainAllConnections()
        let lease = makeLease(.durability, for: coordinator, connectionToken: connectionToken)

        guard await coordinator.startDurability() else {
            lease.release()
            return nil
        }

        return lease
    }

    func reset() {
        generation &+= 1
        headlessBoot?.cancel()
        headlessBoot = nil
        cancelPendingInteractiveStart()
        coordinator?.stopAll()
        coordinator = nil
        isInteractiveStarted = false
        leaseCounts = [:]
    }
}

private extension DashboardServicesManager {
    func existingOrNewCoordinator() -> Coordinator? {
        if let coordinator {
            return coordinator
        }

        coordinator = coordinatorFactory.makeCoordinator()
        return coordinator
    }

    func existingOrHeadlessCoordinator() async -> Coordinator? {
        if let coordinator {
            return coordinator
        }

        if let headlessBoot {
            return await headlessBoot.value
        }

        let boot = Task { await bootHeadless(generation: generation) }
        headlessBoot = boot
        let result = await boot.value
        headlessBoot = nil
        return result
    }

    func bootHeadless(generation bootGeneration: UInt64) async -> Coordinator? {
        let readiness = await headlessBootConfig.bootstrapper.waitWhenReady(deadline: headlessBootConfig.deadline)

        guard readiness == .dashboard else {
            logger.info("Headless boot skipped: \(readiness)")
            return nil
        }

        guard bootGeneration == generation, !Task.isCancelled else { return nil }

        // The dashboard may have created it while the boot waited.
        return existingOrNewCoordinator()
    }

    func leaseCount(for demand: DashboardServicesDemand) -> Int {
        leaseCounts[demand, default: 0]
    }

    func makeLease(
        _ demand: DashboardServicesDemand,
        for coordinator: Coordinator,
        connectionToken: (any ConnectionTokenProtocol)?
    ) -> DashboardServicesLease<Coordinator> {
        leaseCounts[demand, default: 0] += 1

        return DashboardServicesLease(
            coordinator: coordinator,
            demand: demand,
            generation: generation,
            connectionToken: connectionToken
        ) { [weak self] in
            self?.didRelease($0)
        }
    }

    func didRelease(_ lease: DashboardServicesLease<Coordinator>) {
        guard
            lease.generation == generation,
            let coordinator,
            coordinator === lease.coordinator
        else {
            return
        }

        leaseCounts[lease.demand] = max(leaseCount(for: lease.demand) - 1, 0)

        let hasInteractive = leaseCount(for: .interactive) > 0
        let hasDurability = leaseCount(for: .durability) > 0

        if !hasInteractive {
            cancelPendingInteractiveStart()
        }

        switch (lease.demand, hasInteractive, hasDurability) {
        case (_, false, false):
            coordinator.stopAll()
            self.coordinator = nil
            isInteractiveStarted = false
        case (.interactive, false, true):
            coordinator.stopInteractive()
            isInteractiveStarted = false
        default:
            break
        }
    }

    func startInteractiveWhenNeeded(_ coordinator: Coordinator) {
        guard activity.isInBackground, !isInteractiveRequested else {
            startInteractiveNow(coordinator)
            return
        }

        let startGeneration = generation

        pendingInteractiveStart = Task { [weak self, activity] in
            await activity.waitUntilInForeground()

            guard !Task.isCancelled else { return }

            self?.openInteractiveGate(generation: startGeneration)
        }
    }

    func openInteractiveGate(generation gateGeneration: UInt64) {
        guard
            gateGeneration == generation,
            !isInteractiveStarted,
            leaseCount(for: .interactive) > 0,
            let coordinator
        else {
            return
        }

        cancelPendingInteractiveStart()
        startInteractiveNow(coordinator)
    }

    func startInteractiveNow(_ coordinator: Coordinator) {
        isInteractiveStarted = true
        coordinator.startInteractive()
    }

    func cancelPendingInteractiveStart() {
        pendingInteractiveStart?.cancel()
        pendingInteractiveStart = nil
    }
}
