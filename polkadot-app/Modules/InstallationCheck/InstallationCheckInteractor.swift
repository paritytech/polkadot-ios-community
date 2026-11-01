import Foundation
import IssueMonitoring

struct InstallationCheckSettings {
    /// Without a chain connection or signer the check can't start; it tries again instead of spinning forever.
    var retryDelay: Duration = .seconds(5)
    var clock: any Clock<Duration> = ContinuousClock()
    var setupDiagnostic: IssueDiagnostic = NoopIssueDiagnostic()
}

/// Follows the record topic until the service settles a status, which it saves before reporting.
final class InstallationCheckInteractor {
    weak var presenter: InstallationCheckInteractorOutputProtocol?

    private let serviceFactory: ActiveInstallationServiceMaking
    private let settings: InstallationCheckSettings
    private let logger: LoggerProtocol
    private var service: ActiveInstallationServicing?
    private var statusTask: Task<Void, Never>?

    init(
        serviceFactory: ActiveInstallationServiceMaking,
        settings: InstallationCheckSettings = InstallationCheckSettings(),
        logger: LoggerProtocol
    ) {
        self.serviceFactory = serviceFactory
        self.settings = settings
        self.logger = logger
    }

    deinit {
        statusTask?.cancel()
        let service = service
        Task { await service?.throttle() }
    }
}

extension InstallationCheckInteractor: InstallationCheckInteractorInputProtocol {
    func start() {
        statusTask = Task { [weak self] in
            guard let configuration = await self?.makeConfiguration(), let self else { return }

            let service = serviceFactory.makeService()
            self.service = service
            await service.setup(configuration: configuration)
            await waitForSettledStatus(of: service)
        }
    }
}

private extension InstallationCheckInteractor {
    func makeConfiguration() async -> ActiveInstallationConfiguration? {
        while !Task.isCancelled {
            do {
                return try serviceFactory.makeConfiguration()
            } catch {
                logger.error("Installation check can't start: \(error)")
                settings.setupDiagnostic.recordFailure(for: "installation-check", error: error, counters: [:])
                try? await settings.clock.sleep(for: settings.retryDelay)
            }
        }
        return nil
    }

    func waitForSettledStatus(of service: ActiveInstallationServicing) async {
        do {
            for try await status in await service.statusStream where status != .unknown {
                await presenter?.didSettleStatus()
                return
            }
        } catch {
            logger.error("Installation status stream failed: \(error)")
        }
    }
}
