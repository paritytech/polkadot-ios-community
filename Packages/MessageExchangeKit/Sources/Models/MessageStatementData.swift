import Foundation
import SubstrateSdk

public enum StatementData<M: MessageExchange.CodableMessage> {
    case state(MessageExchange.SessionState<M>)
    case multistate(MultiDeviceState)
}

// Indices 0–3 belonged to the retired request/response statements; new builds reject them.
extension StatementData: ScaleCodable {
    static var stateScaleIndex: UInt8 { 4 }
    static var multistateScaleIndex: UInt8 { 5 }

    private var scaleIndex: UInt8 {
        switch self {
        case .state: Self.stateScaleIndex
        case .multistate: Self.multistateScaleIndex
        }
    }

    public init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)

        switch index {
        case Self.stateScaleIndex:
            self = try .state(MessageExchange.SessionState<M>(scaleDecoder: scaleDecoder))
        case Self.multistateScaleIndex:
            self = try .multistate(MultiDeviceState(scaleDecoder: scaleDecoder))
        default:
            throw DynamicScaleDecoderError.unexpectedEnumCase
        }
    }

    public func encode(scaleEncoder: any ScaleEncoding) throws {
        try scaleIndex.encode(scaleEncoder: scaleEncoder)

        switch self {
        case let .state(value):
            try value.encode(scaleEncoder: scaleEncoder)
        case let .multistate(value):
            try value.encode(scaleEncoder: scaleEncoder)
        }
    }
}

extension StatementData: Equatable {}
