import Foundation

final class DeviceTransferRequestInteractor {
    weak var presenter: DeviceTransferRequestInteractorOutputProtocol?

    private let listener: DeviceTransferRequestListening
    private let servicesFactory: DeviceTransferSenderServicesMaking
    private let transfersCounter: OutgoingTransfersCounting
    private let logger: LoggerProtocol
    private var requestTask: Task<Void, Never>?

    init(
        listener: DeviceTransferRequestListening,
        servicesFactory: DeviceTransferSenderServicesMaking,
        transfersCounter: OutgoingTransfersCounting,
        logger: LoggerProtocol
    ) {
        self.listener = listener
        self.servicesFactory = servicesFactory
        self.transfersCounter = transfersCounter
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

    /// A count that can't be read doesn't hold the transfer back.
    func countTransfersStillSending() {
        Task { [weak self, transfersCounter, logger] in
            let count: Int
            do {
                count = try await transfersCounter.countTransfersStillSending()
            } catch {
                logger.error("Sending transfers can't be counted: \(error)")
                count = 0
            }
            self?.presenter?.didReceive(transfersStillSending: count)
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
