import Foundation

final class DeviceTransferRequestInteractor {
    weak var presenter: DeviceTransferRequestInteractorOutputProtocol?

    private let listener: DeviceTransferRequestListening
    private let servicesFactory: DeviceTransferSenderServicesMaking
    private let logger: LoggerProtocol
    private var requestTask: Task<Void, Never>?

    init(
        listener: DeviceTransferRequestListening,
        servicesFactory: DeviceTransferSenderServicesMaking,
        logger: LoggerProtocol
    ) {
        self.listener = listener
        self.servicesFactory = servicesFactory
        self.logger = logger
    }

    deinit {
        requestTask?.cancel()
    }
}

extension DeviceTransferRequestInteractor: DeviceTransferRequestInteractorInputProtocol {
    func setup() {
        requestTask = Task { [weak self, listener, logger] in
            do {
                for try await request in await listener.pendingRequest {
                    self?.presenter?.didReceive(pendingRequest: request)
                }
            } catch {
                logger.error("Device transfer request stream failed: \(error)")
            }
        }
    }

    func decline(_ request: DeviceTransferRequest) {
        do {
            let services = try servicesFactory.makeSenderServices()
            Task { [weak self] in
                await services.coordinator.reject(request)
                self?.presenter?.didDecline()
            }
        } catch {
            logger.error("Device transfer services can't be built to decline: \(error)")
            presenter?.didDecline()
        }
    }
}
