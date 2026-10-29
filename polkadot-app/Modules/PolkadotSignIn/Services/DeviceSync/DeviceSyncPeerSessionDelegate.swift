import Foundation
import Foundation_iOS
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import SubstrateSdkExt

protocol DeviceSyncPeerSessionDelegating: PeerSessionDelegate, TypeErasedDelegateStoring where Message == Data {
    var incomingEnvelopes: AsyncStream<[Chat.DeviceSyncSignalingEnvelope]> { get }
    func finishIncomingEnvelopes()
}

final class DeviceSyncPeerSessionDelegate: DeviceSyncPeerSessionDelegating {
    typealias Message = Data
    typealias EnvelopeDecoder = (Data) throws -> Chat.DeviceSyncSignalingEnvelope?

    private let peerLogger: LoggerProtocol
    private let decodeEnvelope: EnvelopeDecoder
    private let continuation: AsyncStream<[Chat.DeviceSyncSignalingEnvelope]>.Continuation
    let incomingEnvelopes: AsyncStream<[Chat.DeviceSyncSignalingEnvelope]>

    init(
        peerLogger: LoggerProtocol,
        decodeEnvelope: @escaping EnvelopeDecoder = { try Chat.DeviceSyncSignalingEnvelope.fromScaleEncoded($0) }
    ) {
        self.peerLogger = peerLogger
        self.decodeEnvelope = decodeEnvelope
        (incomingEnvelopes, continuation) = AsyncStream.makeStream()
    }

    deinit {
        peerLogger.debug("Deinit")
        finishIncomingEnvelopes()
    }

    func finishIncomingEnvelopes() {
        continuation.finish()
    }

    func peerSession(_: any PeerSessionProtocol, didUpdateState state: PeerSessionState) {
        peerLogger.debug("Device sync peer session state: \(state)")
    }

    func peerSession(_: any PeerSessionProtocol, didInitializeWithOutgoingMessages _: [Data]) {}

    func peerSession(
        _: any PeerSessionProtocol,
        shouldResetAfter _: MessageExchange.InitializationError
    ) -> Bool { true }

    func peerSession(
        _: any PeerSessionProtocol,
        didFinishAddingMessageToQueue _: Data,
        withError error: MessageExchange.AddToQueueError?
    ) {
        if let error { peerLogger.error("Device sync add-to-queue error: \(error)") }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didPostMessages _: [Data],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        if let error { peerLogger.error("Device sync post error: \(error)") }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didDeliverMessages _: [Data],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        if let error { peerLogger.error("Device sync delivery error: \(error)") }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didReceiveMessages messages: [Data],
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        let envelopes = messages.compactMap { data -> Chat.DeviceSyncSignalingEnvelope? in
            do {
                return try decodeEnvelope(data)
            } catch {
                peerLogger.error("Device sync signaling envelope decoding failed: \(error)")
                return nil
            }
        }
        if !envelopes.isEmpty {
            continuation.yield(envelopes)
        }
        respondHandler(.success)
    }

    func peerSessionDidReceiveMessagesError(
        _: any PeerSessionProtocol,
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        peerLogger.error("Device sync incoming message error")
        respondHandler(.success)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldIgnoreStatementAfter _: MessageExchange.IncomingMessageError
    ) -> Bool { true }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldReinitializeAfterSubmitError error: Error
    ) -> Bool {
        if case StatementSubmitError.rejected(.channelPriorityTooLow) = error { return false }
        return true
    }

    func peerSession(
        _: any MessageExchangeKit.PeerSessionProtocol,
        didCompactMessages _: Data,
        originalMessages _: [Data]
    ) {}
}
