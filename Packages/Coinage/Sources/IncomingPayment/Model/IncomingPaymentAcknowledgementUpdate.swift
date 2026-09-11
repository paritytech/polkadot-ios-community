import Foundation
import Operation_iOS

/// A write-only partial update that records when the user was told a settled payment's verdict,
/// leaving everything else untouched. Keyed by `groupId`, like ``IncomingPaymentOutcomeUpdate``.
public struct IncomingPaymentAcknowledgementUpdate: Equatable, Sendable {
    public let groupId: CoinageTxGroupId
    public let acknowledgedAt: Date

    public init(groupId: CoinageTxGroupId, acknowledgedAt: Date) {
        self.groupId = groupId
        self.acknowledgedAt = acknowledgedAt
    }
}

extension IncomingPaymentAcknowledgementUpdate: Operation_iOS.Identifiable {
    public var identifier: String { groupId }
}
