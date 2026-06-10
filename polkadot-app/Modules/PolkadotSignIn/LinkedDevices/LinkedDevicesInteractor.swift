import Foundation

final class LinkedDevicesInteractor {
    weak var presenter: LinkedDevicesInteractorOutputProtocol?

    private let deviceDataProviderFactory: LocalDeviceDataProviderMaking
    private let logger: LoggerProtocol

    private var devicesSubscriptionTask: Task<Void, Error>?

    init(
        deviceDataProviderFactory: LocalDeviceDataProviderMaking = LocalDeviceDataProviderFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.deviceDataProviderFactory = deviceDataProviderFactory
        self.logger = logger
    }

    deinit {
        unsubscribeFromDevices()
    }
}

extension LinkedDevicesInteractor: LinkedDevicesInteractorInputProtocol {
    func setup() {
        subscribeToDevices()
    }
}

private extension LinkedDevicesInteractor {
    func subscribeToDevices() {
        devicesSubscriptionTask = Task { [weak self] in
            do {
                guard let sequence = self?.deviceDataProviderFactory.subscribeDevices() else {
                    return
                }
                for try await devices in sequence {
                    await self?.reportNewDevices(devices)
                }
            } catch {
                self?.logger.error("Local devices subscription error: \(error)")
            }
        }
    }

    func unsubscribeFromDevices() {
        devicesSubscriptionTask?.cancel()
        devicesSubscriptionTask = nil
    }

    @MainActor
    func reportNewDevices(_ devices: [Chat.LocalDevice]) {
        presenter?.didReceiveDevices(devices)
    }
}
