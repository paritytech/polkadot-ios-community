import Foundation
import MessageExchangeKit
import StatementStore
import WebRTC

protocol DeviceTransferRunMaking: Sendable {
    func makeSenderRun(for request: DeviceTransferRequest) throws -> any DeviceTransferRunning
    func makeReceiverRun(
        for request: DeviceTransferRequest,
        senderInstallationId: Data
    ) throws -> any DeviceTransferRunning
    func sendRejection(for request: DeviceTransferRequest) async throws
}

struct DeviceTransferRunConfiguration {
    let connection: StatementStoreConnecting
    let signerManager: StatementStoreSignerManaging
    let ownSignKeyId: String
}

final class DeviceTransferRunFactory: @unchecked Sendable {
    private let configuration: DeviceTransferRunConfiguration
    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let clientFactory: DeviceTransferClientMaking
    private let configFactory: WebRTCConfigMaking
    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let logger: LoggerProtocol

    init(
        configuration: DeviceTransferRunConfiguration,
        keyScheduleFactory: DeviceTransferKeyScheduleMaking,
        clientFactory: DeviceTransferClientMaking,
        webRTC: (configFactory: WebRTCConfigMaking, peerConnectionFactory: RTCPeerConnectionFactory),
        logger: LoggerProtocol
    ) {
        self.configuration = configuration
        self.keyScheduleFactory = keyScheduleFactory
        self.clientFactory = clientFactory
        configFactory = webRTC.configFactory
        peerConnectionFactory = webRTC.peerConnectionFactory
        self.logger = logger
    }
}

extension DeviceTransferRunFactory: DeviceTransferRunMaking {
    func makeSenderRun(for request: DeviceTransferRequest) throws -> any DeviceTransferRunning {
        try makeRun(for: request, role: .sender)
    }

    func makeReceiverRun(
        for request: DeviceTransferRequest,
        senderInstallationId: Data
    ) throws -> any DeviceTransferRunning {
        try makeRun(for: request, role: .receiver(senderInstallationId: senderInstallationId))
    }

    func sendRejection(for request: DeviceTransferRequest) async throws {
        let transport = try makeTransport(for: request, role: .sender)
        try await transport.open(delegate: AnyPeerSessionDelegate(transport.makeSessionDelegate()))
        await transport.sendRejection()
        await transport.close()
    }
}

private extension DeviceTransferRunFactory {
    func makeTransport(for request: DeviceTransferRequest, role: DeviceTransferRole) throws -> DeviceTransferTransport {
        try DeviceTransferTransport(
            context: DeviceTransferSessionContext(
                connection: configuration.connection,
                signerManager: configuration.signerManager,
                ownSignKeyId: configuration.ownSignKeyId,
                keySchedule: keyScheduleFactory.makeKeySchedule(),
                requestId: request.requestId,
                role: role
            ),
            logger: logger
        )
    }

    func makeRun(
        for request: DeviceTransferRequest,
        role: DeviceTransferClientRole
    ) throws -> any DeviceTransferRunning {
        let transportRole: DeviceTransferRole = role == .sender ? .sender : .receiver
        let transport = try makeTransport(for: request, role: transportRole)
        let components = DeviceTransferPeerComponents(
            transport: transport,
            role: transportRole == .sender ? .initiator : .acceptor,
            configFactory: configFactory,
            peerConnectionFactory: peerConnectionFactory,
            logger: logger
        )
        let context = DeviceTransferPeerContext(
            components: components,
            sessionDelegate: transport.makeSessionDelegate(),
            rejections: transport.rejections,
            logger: logger
        )

        return DeviceTransferRun(context: context, clientFactory: clientFactory, role: role)
    }
}

private final class DeviceTransferPeerComponents: DeviceTransferPeerComponentMaking, @unchecked Sendable {
    private let transport: DeviceTransferTransport
    private let role: CallRole
    private let configFactory: WebRTCConfigMaking
    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let logger: LoggerProtocol

    init(
        transport: DeviceTransferTransport,
        role: CallRole,
        configFactory: WebRTCConfigMaking,
        peerConnectionFactory: RTCPeerConnectionFactory,
        logger: LoggerProtocol
    ) {
        self.transport = transport
        self.role = role
        self.configFactory = configFactory
        self.peerConnectionFactory = peerConnectionFactory
        self.logger = logger
    }

    func makeSignalingSession(delegate: AnyPeerSessionDelegate<Data>) async throws -> DeviceSyncSignalingSession {
        try await transport.open(delegate: delegate)
        return DeviceSyncSignalingSession(transport: transport, role: role, peerLogger: logger)
    }

    func makeConnectionFlow(session: DeviceSyncSignalingSession) -> any DevicePeerConnectionFlowing {
        DevicePeerConnectionFlow(
            signaler: session,
            role: role,
            configFactory: configFactory,
            peerConnectionFactory: peerConnectionFactory,
            peerLogger: logger
        )
    }
}
