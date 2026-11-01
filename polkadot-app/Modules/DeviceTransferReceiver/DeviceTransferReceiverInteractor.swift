import Foundation

/// Builds the transfer services when the screen opens; they live as long as the screen.
final class DeviceTransferReceiverInteractor {
    weak var presenter: DeviceTransferReceiverInteractorOutputProtocol?

    private let servicesFactory: DeviceTransferReceiverServicesMaking
    private let statusStore: InstallationStatusStoring
    private let logger: LoggerProtocol
    private var services: DeviceTransferReceiverServices?
    private var statesTask: Task<Void, Never>?

    init(
        servicesFactory: DeviceTransferReceiverServicesMaking,
        statusStore: InstallationStatusStoring,
        logger: LoggerProtocol
    ) {
        self.servicesFactory = servicesFactory
        self.statusStore = statusStore
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

extension DeviceTransferReceiverInteractor: DeviceTransferReceiverInteractorInputProtocol {
    func setup() {
        presenter?.didReceive(oldPhone: statusStore.oldPhone)

        do {
            let services = try servicesFactory.makeReceiverServices()
            self.services = services
            follow(services)
        } catch {
            logger.error("Device transfer services can't be built: \(error)")
            presenter?.didReceive(state: .failed(.failed))
        }
    }

    func startTransfer() {
        guard let services else { return }
        Task { await services.coordinator.start(configuration: services.discoveryConfiguration) }
    }

    func cancelTransfer() {
        guard let services else { return }
        Task { await services.coordinator.cancel() }
    }
}

private extension DeviceTransferReceiverInteractor {
    func follow(_ services: DeviceTransferReceiverServices) {
        statesTask = Task { [weak self, logger] in
            await services.installationService.setup(configuration: services.installationConfiguration)

            do {
                for try await state in await services.coordinator.states {
                    await self?.presenter?.didReceive(state: state)
                }
            } catch {
                logger.error("Device transfer state stream failed: \(error)")
            }
        }
    }
}

private extension InstallationStatusStoring {
    var oldPhone: ActiveInstallation? {
        guard case let .inactive(installation) = status else { return nil }
        return installation
    }
}
