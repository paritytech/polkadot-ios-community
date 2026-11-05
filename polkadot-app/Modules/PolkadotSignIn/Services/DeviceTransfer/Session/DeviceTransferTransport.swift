import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import SubstrateSdkExt

enum DeviceTransferRole {
    case sender
    case receiver
}

struct DeviceTransferSessionContext {
    let connection: StatementStoreConnecting
    let signerManager: StatementStoreSignerManaging
    let ownSignKeyId: String
    let keySchedule: DeviceTransferKeySchedule
    let requestId: String
    let role: DeviceTransferRole
}

/// The per-request transfer session: labels stand in for both accounts, `k_s` encrypts, and statements are
/// short-lived. It wraps outgoing signaling envelopes in `DeviceTransferSessionMessage`, and its session
/// delegate unwraps them, so `DeviceSyncSignalingSession` works over it unchanged.
final class DeviceTransferTransport: @unchecked Sendable {
    let rejections: AsyncStream<Void>

    private let transport: DeviceSyncMessageTransport
    private let rejectionContinuation: AsyncStream<Void>.Continuation
    private let logger: LoggerProtocol

    init(context: DeviceTransferSessionContext, logger: LoggerProtocol) throws {
        let (ownLabel, peerLabel) = Self.labels(for: context)

        let serviceFactory = try MessageExchangeServiceFactory(
            messageExchangeModeProvider: FixedMessageExchangeModeProvider(mode: .identity),
            signManager: context.signerManager,
            encryptionManager: PresharedKeyEncryptionManager(
                presharedKey: context.keySchedule.sessionKey(requestId: context.requestId)
            ),
            deviceEncryptionKeyFactory: nil,
            maxStatementSize: MessageExchangeCoordinatorFactory.Constants.maxDeviceSyncStatementSize,
            accountProvider: FixedSessionAccountProvider(accountId: ownLabel),
            priorityFactory: ShortLivedStatementPriorityFactory(
                lifetimeInSeconds: DeviceTransferConstants.statementLifetimeInSeconds
            ),
            workQueue: DispatchQueue(label: "device.transfer.transport.queue"),
            logger: logger
        )

        transport = DeviceSyncMessageTransport(
            serviceFactory: serviceFactory,
            signerResolver: IdentitySignerResolver(signManager: context.signerManager),
            connection: context.connection,
            sessionRequest: MessageExchange.SessionRequest(
                own: MessageExchange.Own(signKeyId: context.ownSignKeyId, encryptionKeyId: "", pin: nil),
                peer: MessageExchange.Peer(accountId: peerLabel, publicKey: Data(), pin: nil, devices: [])
            ),
            peerLogger: logger
        )

        (rejections, rejectionContinuation) = AsyncStream.makeStream()
        self.logger = logger
    }

    func sendRejection() async {
        await send(wrapped: [.rejected])
    }

    func makeSessionDelegate() -> DeviceSyncPeerSessionDelegate {
        DeviceSyncPeerSessionDelegate(
            peerLogger: logger,
            decoder: DeviceTransferSessionMessageDecoder(rejections: rejectionContinuation)
        )
    }
}

extension DeviceTransferTransport: DeviceSyncMessageTransporting {
    func open(delegate: AnyPeerSessionDelegate<Data>) async throws {
        try await transport.open(delegate: delegate)
    }

    func close() async {
        await transport.close()
        rejectionContinuation.finish()
    }

    func send(_ messages: [Data]) async {
        do {
            let envelopes = try messages.map { try Chat.DeviceSyncSignalingEnvelope.fromScaleEncoded($0) }
            await send(wrapped: envelopes.map { .signaling($0) })
        } catch {
            logger.error("Device transfer signaling encoding failed: \(error)")
        }
    }
}

private extension DeviceTransferTransport {
    static func labels(for context: DeviceTransferSessionContext) -> (own: Data, peer: Data) {
        switch context.role {
        case .sender:
            (context.keySchedule.senderLabel, context.keySchedule.receiverLabel)
        case .receiver:
            (context.keySchedule.receiverLabel, context.keySchedule.senderLabel)
        }
    }

    func send(wrapped messages: [DeviceTransferSessionMessage]) async {
        do {
            try await transport.send(messages.map { try $0.scaleEncoded() })
        } catch {
            logger.error("Device transfer session message encoding failed: \(error)")
        }
    }
}
