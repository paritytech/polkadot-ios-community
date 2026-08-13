import Foundation
import Observation

@Observable
@MainActor
public final class PaymentHistoryViewModel {
    public var items: [Item] = []

    public init() {}
}

public extension PaymentHistoryViewModel {
    struct Item: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let amount: String
        public let date: String
        public let statusText: String
        public let failureReason: String?

        public init(
            id: String,
            title: String,
            amount: String,
            date: String,
            statusText: String,
            failureReason: String?
        ) {
            self.id = id
            self.title = title
            self.amount = amount
            self.date = date
            self.statusText = statusText
            self.failureReason = failureReason
        }
    }
}
