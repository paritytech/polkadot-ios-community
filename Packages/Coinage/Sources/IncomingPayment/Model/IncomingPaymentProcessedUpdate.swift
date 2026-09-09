import Foundation
import Operation_iOS

/// A write-only partial update that flips `processed` on an existing incoming-payment record, leaving
/// every other column untouched. Keyed by the payment's `groupId` (`"productId:paymentId"`), mirroring
/// `CoinPresenceUpdate` — so marking a payment complete never fetch-modify-saves the whole record.
public struct IncomingPaymentProcessedUpdate: Equatable, Sendable {
    public let groupId: CoinageTxGroupId
    public let processed: Bool

    public init(groupId: CoinageTxGroupId, processed: Bool) {
        self.groupId = groupId
        self.processed = processed
    }
}

extension IncomingPaymentProcessedUpdate: Operation_iOS.Identifiable {
    public var identifier: String { groupId }
}
