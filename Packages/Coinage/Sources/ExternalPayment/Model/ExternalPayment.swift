import BigInt
import Foundation
import Operation_iOS
import SubstrateSdk

public struct ExternalPayment: Equatable {
    public enum Stage: Int {
        case plan = 0
        case onboardCoins = 1
        case offboardVouchers = 2
        case completed = 3
        case failed = 4
        case rescheduled = 5
        case partiallyCompleted = 6

        public var isTerminal: Bool {
            switch self {
            case .completed,
                 .failed,
                 .rescheduled,
                 .partiallyCompleted:
                true
            case .plan,
                 .onboardCoins,
                 .offboardVouchers:
                false
            }
        }
    }

    /// Storage identifier, always ``identifier(origin:paymentId:)`` for new records. Legacy rows
    /// carry a bare UUID; the format is opaque to the state machine.
    public let id: String
    public let origin: String
    public let paymentId: String
    public let amountInPlanks: Balance
    public let destination: AccountId
    public let spendScope: SpendScope
    /// Value already delivered to `destination` by finalized unloads of earlier rounds.
    public var settledInPlanks: Balance
    /// Offboarding round: each partial outcome settles what finalized and re-plans the remainder under
    /// a fresh durability group, so round 0's entries are never mistaken for the retry.
    public var round: Int
    public var stage: Stage
    public var failureReason: String?
    public var readyAt: Date
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        origin: String,
        paymentId: String,
        amountInPlanks: Balance,
        destination: AccountId,
        spendScope: SpendScope = .spendable,
        settledInPlanks: Balance = 0,
        round: Int = 0,
        stage: Stage = .plan,
        failureReason: String? = nil,
        readyAt: Date = .init(),
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.init(
            id: Self.identifier(origin: origin, paymentId: paymentId),
            origin: origin,
            amountInPlanks: amountInPlanks,
            destination: destination,
            spendScope: spendScope,
            settledInPlanks: settledInPlanks,
            round: round,
            stage: stage,
            failureReason: failureReason,
            readyAt: readyAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Storage-side initializer: rebuilds the payment from its persisted identifier.
    public init(
        id: String,
        origin: String,
        amountInPlanks: Balance,
        destination: AccountId,
        spendScope: SpendScope = .spendable,
        settledInPlanks: Balance = 0,
        round: Int = 0,
        stage: Stage = .plan,
        failureReason: String? = nil,
        readyAt: Date = .init(),
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.origin = origin
        paymentId = Self.paymentId(fromIdentifier: id, origin: origin)
        self.amountInPlanks = amountInPlanks
        self.destination = destination
        self.spendScope = spendScope
        self.settledInPlanks = settledInPlanks
        self.round = round
        self.stage = stage
        self.failureReason = failureReason
        self.readyAt = readyAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension ExternalPayment {
    /// What is still owed to `destination`.
    var remainingInPlanks: Balance {
        amountInPlanks > settledInPlanks ? amountInPlanks - settledInPlanks : 0
    }

    /// Identity is `(origin, paymentId)`: the same product-supplied id under two origins is two payments.
    static func identifier(origin: String, paymentId: String) -> String {
        "\(origin):\(paymentId)"
    }

    static func paymentId(fromIdentifier id: String, origin: String) -> String {
        let prefix = "\(origin):"
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
    }
}

extension ExternalPayment: Operation_iOS.Identifiable {
    public var identifier: String { id }
}
