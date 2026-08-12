import BigInt
import Foundation
import PolkadotUI

@MainActor
final class PaymentHistoryPresenter {
    weak var view: (any PaymentHistoryViewProtocol)?
    let wireframe: PaymentHistoryWireframeProtocol
    let interactor: PaymentHistoryInteractorInputProtocol

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        interactor: PaymentHistoryInteractorInputProtocol,
        wireframe: PaymentHistoryWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension PaymentHistoryPresenter: PaymentHistoryPresenterProtocol {
    func setup() {
        interactor.setup()
    }
}

extension PaymentHistoryPresenter: PaymentHistoryInteractorOutputProtocol {
    func didReceive(records: [W3sPaymentRecord]) {
        let items = records.map(makeItem(from:))
        view?.applyItems(items)
    }
}

private extension PaymentHistoryPresenter {
    func makeItem(from record: W3sPaymentRecord) -> PaymentHistoryViewModel.Item {
        let title = record.merchantName ?? record.paymentId
        let statusText = record.status.title
        let failureReason = record.status.failureReason

        return PaymentHistoryViewModel.Item(
            id: record.paymentId,
            title: title,
            amount: record.amountString,
            date: dateFormatter.string(from: record.createdAt),
            statusText: statusText,
            failureReason: failureReason
        )
    }
}

private extension W3sPaymentRecord.Status {
    var title: String {
        switch self {
        case .pending: "Pending"
        case .submitted: "Submitted"
        case .sent: "Sent"
        case .claimed: "Claimed"
        case .failed: "Failed"
        case .revoked: "Revoked"
        }
    }

    var failureReason: String? {
        guard case let .failed(reason) = self else {
            return nil
        }
        return reason
    }
}
