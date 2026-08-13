import Foundation
import SDKLogger

final class PaymentHistoryInteractor {
    weak var presenter: PaymentHistoryInteractorOutputProtocol?

    private let historyStore: W3sPaymentHistoryStoring
    private let logger: SDKLoggerProtocol?

    private var observationTask: Task<Void, Never>?

    init(
        historyStore: W3sPaymentHistoryStoring,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.historyStore = historyStore
        self.logger = logger
    }

    deinit {
        observationTask?.cancel()
    }
}

extension PaymentHistoryInteractor: PaymentHistoryInteractorInputProtocol {
    func setup() {
        observationTask?.cancel()
        let store = historyStore
        observationTask = Task { [weak self] in
            do {
                for try await records in store.observeAll() {
                    await self?.presenter?.didReceive(records: records)
                }
            } catch {
                self?.logger?.error("PaymentHistory observation failed: \(error)")
            }
        }
    }
}
