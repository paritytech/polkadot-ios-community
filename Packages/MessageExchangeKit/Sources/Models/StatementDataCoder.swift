import Foundation
import SubstrateSdk
import CryptoKit
import SDKLogger

public enum StatementDataDecodingError: Error {
    case decodingFailed
    case decryptionFailed
}

public enum StatementDataEncodingError: Error {
    case encodingFailed
    case encryptionFailed
}

public enum StatementDataDecodingResult<M: MessageExchange.CodableMessage> {
    case statementData(StatementData<M>)
    /// The messages could not be decoded; what survived is the response (if any) and the request id.
    case partial(response: MessageExchange.Response?, requestId: String, error: Error)
}

public protocol StatementDataCoding {
    func decodeFromScaleEncodedPayload<M: MessageExchange.CodableMessage>(
        _ payload: Data,
        senderAccountId: Data?,
        route: PeerSessionRoute
    ) throws -> StatementDataDecodingResult<M>

    func encodeToScaleEncodedPayload(
        _ statementData: StatementData<some MessageExchange.CodableMessage>,
        route: PeerSessionRoute
    ) throws -> Data
}

public final class StatementDataCoder: StatementDataCoding {
    private let encryptor: MessageExchangeEncrypting
    private let padding: StatementPayloadPadding
    private let logger: SDKLoggerProtocol?

    public init(
        encryptor: MessageExchangeEncrypting,
        padding: StatementPayloadPadding,
        logger: SDKLoggerProtocol?
    ) {
        self.encryptor = encryptor
        self.padding = padding
        self.logger = logger
    }

    public func decodeFromScaleEncodedPayload<M: MessageExchange.CodableMessage>(
        _ payload: Data,
        senderAccountId _: Data?,
        route _: PeerSessionRoute
    ) throws -> StatementDataDecodingResult<M> {
        let encryptedData: Data
        let decryptedData: Data

        do {
            let decoder = try ScaleDecoder(data: payload)
            encryptedData = try Data(scaleDecoder: decoder)
        } catch {
            throw StatementDataDecodingError.decodingFailed
        }

        do {
            decryptedData = try encryptor.decrypt(encryptedData)
        } catch {
            throw StatementDataDecodingError.decryptionFailed
        }

        do {
            let decoder = try ScaleDecoder(data: decryptedData)
            let statementData = try StatementData<M>(scaleDecoder: decoder)

            return .statementData(statementData)
        } catch {
            guard let partial: StatementDataDecodingResult<M> = Self.decodePartial(from: decryptedData, error: error)
            else {
                throw StatementDataDecodingError.decodingFailed
            }

            return partial
        }
    }

    public func encodeToScaleEncodedPayload(
        _ statementData: StatementData<some MessageExchange.CodableMessage>,
        route _: PeerSessionRoute
    ) throws -> Data {
        let statementScaleData: Data
        let encryptedData: Data
        let result: Data

        do {
            statementScaleData = try statementData.scaleEncoded()
        } catch {
            throw StatementDataEncodingError.encodingFailed
        }

        do {
            encryptedData = try encryptor.encrypt(padding.pad(statementScaleData))
        } catch {
            throw StatementDataEncodingError.encryptionFailed
        }

        do {
            result = try encryptedData.scaleEncoded()
        } catch {
            throw StatementDataEncodingError.encodingFailed
        }

        return result
    }
}

private extension StatementDataCoder {
    static func decodePartial<M: MessageExchange.CodableMessage>(
        from decryptedData: Data,
        error: Error
    ) -> StatementDataDecodingResult<M>? {
        guard
            let decoder = try? ScaleDecoder(data: decryptedData),
            let index = try? UInt8(scaleDecoder: decoder)
        else {
            return nil
        }

        guard index == StatementData<M>.stateScaleIndex else {
            return nil
        }

        return SessionStateFallbackData.decodePartial(from: decoder, error: error)
    }
}

extension SessionStateFallbackData {
    static func decodePartial<M: MessageExchange.CodableMessage>(
        from decoder: ScaleDecoding,
        error: Error
    ) -> StatementDataDecodingResult<M>? {
        guard
            let fallback = try? SessionStateFallbackData(scaleDecoder: decoder),
            let requestId = fallback.requestId
        else {
            return nil
        }

        return .partial(response: fallback.response, requestId: requestId, error: error)
    }
}
