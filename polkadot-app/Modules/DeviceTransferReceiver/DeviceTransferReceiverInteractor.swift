import Foundation

struct DeviceTransferReceiverModuleSettings {
    var clock: any Clock<Duration> = ContinuousClock()
    var publishRetry = ActiveInstallationPublishRetry()
}

/// Builds the transfer services when the screen opens; they live as long as the screen.
final class DeviceTransferReceiverInteractor {
    weak var presenter: DeviceTransferReceiverInteractorOutputProtocol?

    private let servicesFactory: DeviceTransferReceiverServicesMaking
    private let statusStore: InstallationStatusStoring
    private let screenSleep: OperatingSystemMediating
    private let settings: DeviceTransferReceiverModuleSettings
    private let logger: LoggerProtocol
    private var services: DeviceTransferReceiverServices?
    private var statesTask: Task<Void, Never>?
    private var waitTimerTask: Task<Void, Never>?

    init(
        servicesFactory: DeviceTransferReceiverServicesMaking,
        statusStore: InstallationStatusStoring,
        screenSleep: OperatingSystemMediating,
        settings: DeviceTransferReceiverModuleSettings = DeviceTransferReceiverModuleSettings(),
        logger: LoggerProtocol
    ) {
        self.servicesFactory = servicesFactory
        self.statusStore = statusStore
        self.screenSleep = screenSleep
        self.settings = settings
        self.logger = logger
    }

    deinit {
        statesTask?.cancel()
        waitTimerTask?.cancel()
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

    /// Withdraws a pending request first, so the old phone isn't asked after it was replaced.
    func activateWithoutTransfer() {
        guard let services else { return }
        Task { [weak self, logger, publishRetry = settings.publishRetry] in
            await services.coordinator.cancel()

            do {
                try await services.installationService.publishSelf(retry: publishRetry)
                self?.presenter?.didActivateWithoutTransfer()
            } catch {
                logger.error("Activation without transfer failed: \(error)")
                self?.presenter?.didFailActivation()
            }
        }
    }
}

private extension DeviceTransferReceiverInteractor {
    func follow(_ services: DeviceTransferReceiverServices) {
        statesTask = Task { [weak self, logger] in
            await services.installationService.setup(configuration: services.installationConfiguration)

            do {
                for try await state in await services.coordinator.states {
                    await self?.handle(state)
                }
            } catch {
                logger.error("Device transfer state stream failed: \(error)")
            }
        }
    }
}

private extension DeviceTransferReceiverInteractor {
    /// How long the old phone gets to answer before activating without it is offered.
    static let oldPhoneAnswerDelay: Duration = .seconds(5)

    @MainActor
    func handle(_ state: DeviceTransferState) {
        updateWaitTimer(for: state)
        updateScreenSleep(for: state)
        presenter?.didReceive(state: state)
    }

    @MainActor
    func updateWaitTimer(for state: DeviceTransferState) {
        guard case .waitingForSender = state else {
            waitTimerTask?.cancel()
            waitTimerTask = nil
            return
        }
        guard waitTimerTask == nil else { return }

        waitTimerTask = Task { [weak self, clock = settings.clock] in
            guard await (try? clock.sleep(for: Self.oldPhoneAnswerDelay)) != nil else { return }
            self?.presenter?.didWaitTooLongForOldPhone()
        }
    }

    /// The run pauses when the phone locks, so the screen stays on while one is in progress.
    @MainActor
    func updateScreenSleep(for state: DeviceTransferState) {
        if state.isRunning {
            screenSleep.disableScreenSleep()
        } else if state != .idle {
            screenSleep.enableScreenSleep()
        }
    }
}

private extension InstallationStatusStoring {
    var oldPhone: ActiveInstallation? {
        guard case let .inactive(installation) = status else { return nil }
        return installation
    }
}
