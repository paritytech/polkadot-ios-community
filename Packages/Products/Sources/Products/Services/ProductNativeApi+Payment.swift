import AsyncExtensions
import Foundation
import SubstrateSdk
import BigInt

public struct PaymentBalance: Encodable {
    @StringCodable public var available: Balance

    public init(available: Balance) {
        self.available = available
    }
}

/// Payment status as seen by product scripts.
public enum HostPaymentStatus: Sendable, Equatable {
    case processing
    case completed
    case failed(reason: String)
}

/// Receipt returned to the product after initiating a payment.
public struct PaymentReceipt: Sendable {
    public let paymentId: String

    public init(paymentId: String) {
        self.paymentId = paymentId
    }
}

/// Product-supplied idempotency key for a top-up (`host_payment_top_up`).
public typealias PaymentTopUpId = String

/// Top-up status as seen by product scripts. Mirrors `host_payment_top_up_status`. Terminal:
/// `claimed(finalized: true)`, `claimedPartially`, `notClaimed`.
public enum HostPaymentTopUpStatus: Sendable, Equatable {
    case detecting
    case claiming
    case claimed(finalized: Bool)
    case claimedPartially(actualClaimed: Balance)
    case notClaimed
}

/// Typed error for `host_payment_top_up`, serialized to JS via `HostCallCodedError` so product
/// scripts can reconstruct the `PaymentTopUpErr` variant.
public enum HostPaymentTopUpError: HostCallCodedError {
    case invalidSource
    case alreadyExists
    case sourceBusy
    case unknown(reason: String)

    public var code: String {
        switch self {
        case .invalidSource: "InvalidSource"
        case .alreadyExists: "AlreadyExists"
        case .sourceBusy: "SourceBusy"
        case .unknown: "Unknown"
        }
    }

    public var message: String {
        switch self {
        case .invalidSource: "The source account was not found or is invalid"
        case .alreadyExists: "A top up for the given id already exists"
        case .sourceBusy: "The source is already used by another active top up"
        case let .unknown(reason): reason
        }
    }
}

// MARK: - Wire DTOs

/// Decoded request for `paymentTopUp`. `amount`/`id` sit alongside the flat `sourceTag`/`sourceKey…`
/// fields, so `source` is decoded from the same container.
public struct PaymentTopUpRequestDto: Decodable {
    @StringCodable public var amount: Balance
    public let id: PaymentTopUpId
    public let source: PaymentTopUpSource

    private enum CodingKeys: String, CodingKey {
        case amount
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _amount = try container.decode(StringCodable<Balance>.self, forKey: .amount)
        id = try container.decode(PaymentTopUpId.self, forKey: .id)
        source = try PaymentTopUpSource(from: decoder)
    }
}

/// Decoded request for `paymentTopUpStatusSubscribe`.
public struct PaymentTopUpStatusSubscribeDto: Decodable {
    public let id: PaymentTopUpId
}

/// Wire representation of ``HostPaymentTopUpStatus`` — a tagged struct (`tag` + the fields the tag
/// carries), encoded to the bridge via `toScaleCompatibleJSON()`.
public struct HostPaymentTopUpStatusDto: Encodable {
    public let tag: String
    public let finalized: Bool?
    @OptionStringCodable public var actualClaimed: Balance?

    public init(status: HostPaymentTopUpStatus) {
        switch status {
        case .detecting:
            tag = "Detecting"
            finalized = nil
            _actualClaimed = OptionStringCodable(wrappedValue: nil)
        case .claiming:
            tag = "Claiming"
            finalized = nil
            _actualClaimed = OptionStringCodable(wrappedValue: nil)
        case let .claimed(finalized):
            tag = "Claimed"
            self.finalized = finalized
            _actualClaimed = OptionStringCodable(wrappedValue: nil)
        case let .claimedPartially(actualClaimed):
            tag = "ClaimedPartially"
            finalized = nil
            _actualClaimed = OptionStringCodable(wrappedValue: actualClaimed)
        case .notClaimed:
            tag = "NotClaimed"
            finalized = nil
            _actualClaimed = OptionStringCodable(wrappedValue: nil)
        }
    }
}
