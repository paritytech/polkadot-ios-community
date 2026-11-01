import Foundation
import StructuredConcurrency
import IssueMonitoring

struct DeviceTransferSenderModuleSettings {
    var clock: any Clock<Duration> = ContinuousClock()
    /// How long the old phone waits for the new phone's record before the root decides without it.
    var handOverTimeout: Duration = .seconds(120)
    var setupDiagnostic: IssueDiagnostic = NoopIssueDiagnostic()
}

/// Builds the sender services when the transfer is confirmed; they live as long as the screen.
final class DeviceTransferSenderInteractor {
    weak var presenter: DeviceTransferSenderInteractorOutputProtocol?

    private let servicesFactory: DeviceTransferSenderServicesMaking
    private let dashboardServices: DashboardServicesResetting
    private let screenSleep: OperatingSystemMediating
    private let settings: DeviceTransferSenderModuleSettings
    private let logger: LoggerProtocol
    private var services: DeviceTransferSenderServices?
    private var statesTask: Task<Void, Never>?

    init(
        servicesFactory: DeviceTransferSenderServicesMaking,
        dashboardServices: DashboardServicesResetting,
        screenSleep: OperatingSystemMediating,
        settings: DeviceTransferSenderModuleSettings = DeviceTransferSenderModuleSettings(),
        logger: LoggerProtocol
    ) {
        self.servicesFactory = servicesFactory
        self.dashboardServices = dashboardServices
        self.screenSleep = screenSleep
        self.settings = settings
        self.logger = logger
    }

    deinit {
        statesTask?.cancel()
        let services = services
        Task {
            await services?.coordinator.cancel()
            await services?.installationService.throttle()
        }
    }
}

extension DeviceTransferSenderInteractor: DeviceTransferSenderInteractorInputProtocol {
    /// Dashboard services stop first, so nothing writes to the database the transfer reads from.
    func start(_ request: DeviceTransferRequest) {
        dashboardServices.reset()

        do {
            let services = try servicesFactory.makeSenderServices()
            self.services = services
            follow(services)
            Task { await services.coordinator.confirm(request) }
        } catch {
            logger.error("Device transfer sender services can't be built: \(error)")
            settings.setupDiagnostic.recordFailure(for: "sender", error: error, counters: [:])
            presenter?.didReceive(state: .failed(.failed))
        }
    }

    func cancel() {
        guard let services else { return }
        Task { await services.coordinator.cancel() }
    }
}

@MainActor
private extension DeviceTransferSenderInteractor {
    func follow(_ services: DeviceTransferSenderServices) {
        statesTask = Task { [weak self, logger] in
            do {
                for try await state in await services.coordinator.states {
                    self?.handle(state)

                    if state == .completed {
                        await self?.waitForHandOver(services)
                        self?.presenter?.didHandOver()
                        return
                    }
                }
            } catch {
                logger.error("Device transfer sender state stream failed: \(error)")
            }
        }
    }

    func handle(_ state: DeviceTransferState) {
        if state.isRunning {
            screenSleep.disableScreenSleep()
        } else if state != .idle {
            screenSleep.enableScreenSleep()
        }
        presenter?.didReceive(state: state)
    }

    /// The new phone publishes its record right after the run, which saves this phone as inactive.
    func waitForHandOver(_ services: DeviceTransferSenderServices) async {
        await services.installationService.setup(configuration: services.installationConfiguration)

        let statuses = await services.installationService.statusStream
        _ = try? await withTimeout(settings.handOverTimeout, clock: settings.clock) {
            for try await status in statuses where status != .unknown && status != .active {
                return
            }
        }

        await services.installationService.throttle()
    }
}
