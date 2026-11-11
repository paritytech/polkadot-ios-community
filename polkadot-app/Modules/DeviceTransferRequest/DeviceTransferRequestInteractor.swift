import Foundation

final class DeviceTransferRequestInteractor {
    weak var presenter: DeviceTransferRequestInteractorOutputProtocol?

    private let listener: DeviceTransferRequestListening
    private let servicesFactory: DeviceTransferSenderServicesMaking
    private let paymentsCounter: PendingPaymentsCounting
    private let logger: LoggerProtocol
    private var requestTask: Task<Void, Never>?

    init(
        listener: DeviceTransferRequestListening,
        servicesFactory: DeviceTransferSenderServicesMaking,
        paymentsCounter: PendingPaymentsCounting,
        logger: LoggerProtocol
    ) {
        self.listener = listener
        self.servicesFactory = servicesFactory
        self.paymentsCounter = paymentsCounter
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
    func countPendingPayments() {
        Task { [weak self, paymentsCounter, logger] in
            let payments: PendingPayments
            do {
                payments = try await paymentsCounter.countPendingPayments()
            } catch {
                logger.error("Pending payments can't be counted: \(error)")
                payments = PendingPayments(receiving: 0, sending: 0)
            }
            self?.presenter?.didReceive(pendingPayments: payments)
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
