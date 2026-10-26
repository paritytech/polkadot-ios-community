import Foundation
import Foundation_iOS
import MessageExchangeKit
import SubstrateSdk
import SubstrateSdkExt

/// Unwraps incoming `DeviceTransferSessionMessage`s for the device sync delegate behind it: signaling envelopes
/// reach it as plain envelope bytes, and `rejected` goes to `onRejected` instead.
final class DeviceTransferSessionDelegate: PeerSessionDelegate, TypeErasedDelegateStoring {
    typealias Message = Data

    private let target: AnyPeerSessionDelegate<Data>
    private let onRejected: () -> Void
    private let logger: LoggerProtocol

    init(target: AnyPeerSessionDelegate<Data>, onRejected: @escaping () -> Void, logger: LoggerProtocol) {
        self.target = target
        self.onRejected = onRejected
        self.logger = logger
    }

    func peerSession(
        _ peerSession: any PeerSessionProtocol,
        didReceiveMessages messages: [Data],
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        let envelopes = messages.compactMap(unwrap)
        target.peerSession(peerSession, didReceiveMessages: envelopes, respondHandler: respondHandler)
    }

    func peerSession(_ peerSession: any PeerSessionProtocol, didUpdateState state: PeerSessionState) {
        target.peerSession(peerSession, didUpdateState: state)
    }

    func peerSession(_ peerSession: any PeerSessionProtocol, didInitializeWithOutgoingMessages messages: [Data]) {
        target.peerSession(peerSession, didInitializeWithOutgoingMessages: messages)
    }

    func peerSession(
        _ peerSession: any PeerSessionProtocol,
        shouldResetAfter error: MessageExchange.InitializationError
    ) -> Bool {
        target.peerSession(peerSession, shouldResetAfter: error)
    }

    func peerSession(
        _ peerSession: any PeerSessionProtocol,
        didFinishAddingMessageToQueue message: Data,
        withError error: MessageExchange.AddToQueueError?
    ) {
        target.peerSession(peerSession, didFinishAddingMessageToQueue: message, withError: error)
    }

    func peerSession(
        _ peerSession: any PeerSessionProtocol,
        didPostMessages messages: [Data],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        target.peerSession(peerSession, didPostMessages: messages, withError: error)
    }

    func peerSession(
        _ peerSession: any PeerSessionProtocol,
        didDeliverMessages messages: [Data],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        target.peerSession(peerSession, didDeliverMessages: messages, withError: error)
    }

    func peerSessionDidReceiveMessagesError(
        _ peerSession: any PeerSessionProtocol,
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        target.peerSessionDidReceiveMessagesError(peerSession, respondHandler: respondHandler)
    }

    func peerSession(
        _ peerSession: any PeerSessionProtocol,
        shouldIgnoreStatementAfter error: MessageExchange.IncomingMessageError
    ) -> Bool {
        target.peerSession(peerSession, shouldIgnoreStatementAfter: error)
    }

    func peerSession(_ peerSession: any PeerSessionProtocol, shouldReinitializeAfterSubmitError error: Error) -> Bool {
        target.peerSession(peerSession, shouldReinitializeAfterSubmitError: error)
    }

    func peerSession(
        _ peerSession: any PeerSessionProtocol,
        didCompactMessages compactedMessage: Data,
        originalMessages: [Data]
    ) {
        target.peerSession(peerSession, didCompactMessages: compactedMessage, originalMessages: originalMessages)
    }
}

private extension DeviceTransferSessionDelegate {
    func unwrap(_ message: Data) -> Data? {
        do {
            switch try DeviceTransferSessionMessage.fromScaleEncoded(message) {
            case .rejected:
                onRejected()
                return nil
            case let .signaling(envelope):
                return try envelope.scaleEncoded()
            }
        } catch {
            logger.error("Device transfer session message decoding failed: \(error)")
            return nil
        }
    }
}
