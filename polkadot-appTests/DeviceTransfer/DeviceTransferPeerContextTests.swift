@testable import polkadot_app
import Foundation
import MessageExchangeKit
import SubstrateSdk
import Testing

/// Time runs a thousand times faster here: the 15 min idle deadline is 0.9 s and retry delays are milliseconds.
@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferPeerContextTests {
    private let components = TransferContextComponents()
    private let rejections = AsyncStream.makeStream(of: Void.self)

    @Test("A completed transfer ends the run and closes the signaling session")
    func completedTransferEndsRun() async throws {
        try await makeContext().run { _ in }

        #expect(components.flowCount == 1)
        #expect(components.transport?.didClose == true)
    }

    @Test("A dropped connection is replaced and the transfer completes on the next one")
    func droppedConnectionIsReplaced() async throws {
        let attempts = DeviceSyncTestEventRecorder<Void>()

        try await makeContext().run { _ in
            attempts.record(())
            if attempts.snapshot.count == 1 { throw DeviceTransferRunError.disconnected }
        }

        #expect(components.flowCount == 2)
    }

    @Test("A reconnect from the other phone replaces the attempt in progress at once, without a restart delay")
    func reconnectReplacesAttempt() async throws {
        let sleeps = DeviceSyncTestEventRecorder<Duration>()
        let delegate = DeviceSyncPeerSessionDelegate(peerLogger: MockLogger())
        let context = makeContext(sessionDelegate: delegate) { duration in
            sleeps.record(duration)
            try await Task.sleep(for: duration / 1_000)
        }
        let attempts = DeviceSyncTestEventRecorder<Void>()
        let components = components

        try await context.run { _ in
            attempts.record(())
            guard attempts.snapshot.count == 1 else { return }

            let session = try #require(components.session)
            try await session.send([.offer(SdpCoderTests.validOfferSdp)])
            let offerId = try #require(await session.currentReconnectOfferId())
            try Self.deliverReconnected(offerId: offerId, to: delegate)
            try await Task.sleep(for: .seconds(30))
        }

        #expect(components.flowCount == 2)
        #expect(!sleeps.snapshot.contains(DeviceSyncRestartDelayPolicy().delay(forAttempt: 1)))
    }

    @Test("An abort from the other phone ends the run without another connection")
    func abortEndsRun() async throws {
        await #expect(throws: DeviceTransferRunError.aborted(.userCancelled)) {
            try await makeContext().run { _ in throw DeviceTransferRunError.aborted(.userCancelled) }
        }

        #expect(components.flowCount == 1)
    }

    @Test("A rejection ends the run while the connection is still being set up")
    func rejectionEndsRun() async throws {
        let context = makeContext()
        let continuation = rejections.continuation

        await #expect(throws: DeviceTransferContextError.rejected) {
            try await context.run { _ in
                continuation.yield()
                try await Task.sleep(for: .seconds(30))
            }
        }
    }

    @Test("Without a statement or an open channel for the idle deadline, the run ends")
    func idleDeadlineEndsRun() async throws {
        await #expect(throws: DeviceTransferContextError.idleTimeout) {
            try await makeContext().run { _ in throw DeviceTransferRunError.disconnected }
        }
    }

    @Test("An open data channel keeps a transfer that outlasts the idle deadline going")
    func openChannelHoldsIdleDeadline() async throws {
        try await makeContext().run { flow in
            let mock = try #require(flow as? MockDevicePeerConnectionFlow)
            await mock.sendState(.connected)
            try await Task.sleep(for: .milliseconds(1_500))
        }
    }
}

private extension DeviceTransferPeerContextTests {
    func makeContext(
        sessionDelegate: DeviceSyncPeerSessionDelegate = DeviceSyncPeerSessionDelegate(peerLogger: MockLogger()),
        sleep: @escaping DeviceSyncSleep = { try await Task.sleep(for: $0 / 1_000) }
    ) -> DeviceTransferPeerContext {
        DeviceTransferPeerContext(
            components: components,
            sessionDelegate: sessionDelegate,
            rejections: rejections.stream,
            settings: DeviceTransferPeerContextSettings(sleep: sleep),
            logger: MockLogger()
        )
    }

    static func deliverReconnected(offerId: String, to delegate: DeviceSyncPeerSessionDelegate) throws {
        let envelope = Chat.DeviceSyncSignalingEnvelope(offerId: offerId, message: .reconnected)
        try delegate.peerSession(
            MockDeviceSyncPeerSession(),
            didReceiveMessages: [envelope.scaleEncoded()],
            respondHandler: { _ in }
        )
    }
}

private final class TransferContextComponents: DeviceTransferPeerComponentMaking, @unchecked Sendable {
    private let lock = NSLock()
    private var flows: [MockDevicePeerConnectionFlow] = []
    private var latestTransport: MockDeviceSyncMessageTransport?
    private var latestSession: DeviceSyncSignalingSession?

    var flowCount: Int { lock.withLock { flows.count } }
    var transport: MockDeviceSyncMessageTransport? { lock.withLock { latestTransport } }
    var session: DeviceSyncSignalingSession? { lock.withLock { latestSession } }

    func makeSignalingSession(delegate: AnyPeerSessionDelegate<Data>) async throws -> DeviceSyncSignalingSession {
        let transport = MockDeviceSyncMessageTransport()
        try await transport.open(delegate: delegate)
        let session = DeviceSyncSignalingSession(transport: transport, role: .initiator, peerLogger: MockLogger())
        lock.withLock {
            latestTransport = transport
            latestSession = session
        }
        return session
    }

    func makeConnectionFlow(session _: DeviceSyncSignalingSession) -> any DevicePeerConnectionFlowing {
        let flow = MockDevicePeerConnectionFlow(startResult: .success(()))
        lock.withLock { flows.append(flow) }
        return flow
    }
}
