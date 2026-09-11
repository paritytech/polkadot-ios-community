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
    /// Money moved, but less than requested. Reported on the wire as `Completed` with the delivered
    /// amount in `value`, so products that reconcile can, and legacy ones keep the parity behaviour.
    case partiallyCompleted(settledInPlanks: Balance)
    case failed(reason: String)
}

/// Coded `paymentRequest` errors. Messages keep the legacy strings the current
/// container.js matches on.
public enum HostPaymentRequestError: Error, Hashable {
    case rejected
    case insufficientBalance
    case alreadyExists
    case unknown(String)

    public var code: String {
        switch self {
        case .rejected: "Rejected"
        case .insufficientBalance: "InsufficientBalance"
        case .alreadyExists: "AlreadyExists"
        case .unknown: "Unknown"
        }
    }

    public var message: String {
        switch self {
        case .rejected: "payment rejected"
        case .insufficientBalance: "insufficient balance"
        case .alreadyExists: "A payment for the given id already exists"
        case let .unknown(reason): reason
        }
    }

    public static func wrapping(_ error: Error) -> HostPaymentRequestError {
        error as? HostPaymentRequestError ?? .unknown(error.localizedDescription)
    }
}

extension HostPaymentRequestError: HostCallCodedError {}

// MARK: - Wire DTOs

/// Decoded request for `paymentRequest`. Both byte fields are hex strings on the wire
/// and must be exactly 32 bytes.
public struct PaymentRequestDto: Decodable {
    public let id: PaymentRequestId
    @StringCodable public var amount: Balance
    public let destination: AccountId

    private enum CodingKeys: String, CodingKey {
        case id
        case amount
        case destination = "destinationHex"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFixedHexBytes(forKey: .id)
        _amount = try container.decode(StringCodable<Balance>.self, forKey: .amount)
        destination = try container.decodeFixedHexBytes(forKey: .destination)
    }
}

/// Decoded request for `paymentStatusSubscribe`.
public struct PaymentStatusSubscribeDto: Decodable {
    public let paymentId: PaymentRequestId

    private enum CodingKeys: String, CodingKey {
        case paymentId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paymentId = try container.decodeFixedHexBytes(forKey: .paymentId)
    }
}

/// Wire representation of ``HostPaymentStatus``: a tagged struct encoded via `toScaleCompatibleJSON()`.
public struct HostPaymentStatusDto: Encodable {
    public let tag: String
    public let value: String?

    public init(status: HostPaymentStatus) {
        switch status {
        case .processing:
            tag = "Processing"
            value = nil
        case .completed:
            tag = "Completed"
            value = nil
        case let .partiallyCompleted(settledInPlanks):
            tag = "Completed"
            value = String(settledInPlanks)
        case let .failed(reason):
            tag = "Failed"
            value = reason
        }
    }
}

// MARK: - Fixed-length hex decoding

enum PaymentWireBytes {
    static let length = 32
}

private extension KeyedDecodingContainer {
    func decodeFixedHexBytes(forKey key: Key) throws -> Data {
        let bytes = try decode(HexCodable<Data>.self, forKey: key).wrappedValue

        guard bytes.count == PaymentWireBytes.length else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "expected \(PaymentWireBytes.length) bytes, got \(bytes.count)"
            )
        }

        return bytes
    }
}

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
    case notFound(String)
    case unknown(reason: String)

    public var code: String {
        switch self {
        case .invalidSource: "InvalidSource"
        case .alreadyExists: "AlreadyExists"
        case .sourceBusy: "SourceBusy"
        case .notFound: "NotFound"
        case .unknown: "Unknown"
        }
    }

    public var message: String {
        switch self {
        case .invalidSource: "The source account was not found or is invalid"
        case .alreadyExists: "A top up for the given id already exists"
        case .sourceBusy: "The source is already used by another active top up"
        case let .notFound(paymentId): "Top up with given payment id not found \(paymentId)"
        case let .unknown(reason): reason
        }
    }
}

// MARK: - Wire DTOs

/// Decoded request for `paymentTopUp`. `amount`/`id` sit alongside the flat `sourceTag`/`sourceKey…`
/// fields, so `source` is decoded from the same container.
public struct PaymentTopUpRequestDto: Decodable {
    @StringCodable public var amount: Balance
    @HexCodable public var id: PaymentTopUpId
    public let source: PaymentTopUpSource

    private enum CodingKeys: String, CodingKey {
        case amount
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _amount = try container.decode(StringCodable<Balance>.self, forKey: .amount)
        _id = try container.decode(HexCodable<PaymentTopUpId>.self, forKey: .id)
        // The source fields are flat siblings of `amount`/`id`, not a nested object, so `source`
        // decodes from the top-level decoder rather than from a `source` key.
        source = try PaymentTopUpSource(from: decoder)
    }
}

/// Decoded request for `paymentTopUpStatusSubscribe`.
public struct PaymentTopUpStatusSubscribeDto: Decodable {
    @HexCodable public var id: PaymentTopUpId
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
