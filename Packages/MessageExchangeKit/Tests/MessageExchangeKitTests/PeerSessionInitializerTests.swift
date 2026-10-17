import CryptoKit
import Foundation
import Foundation_iOS
import StatementStore
import SubstrateSdk
import Testing
@testable import MessageExchangeKit

struct PeerSessionInitializerTests {
    let ownAccountId = Data(repeating: 1, count: 32)
    let peerDeviceA = Data(repeating: 2, count: 32)
    let peerDeviceB = Data(repeating: 3, count: 32)
    let coder: StatementDataCoder

    init() throws {
        let encryptor = try X25519ChaChaPolyEncryptorFactory(privateKey: Curve25519.KeyAgreement.PrivateKey())
            .makeEncryptor(remotePublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        coder = StatementDataCoder(
            encryptor: encryptor,
            padding: StatementPayloadPadding(maxPayloadSize: 4_096),
            logger: nil
        )
    }

    @Test func junkWithMaxExpiryOnOwnTopicDoesNotSeedTheExpiry() async throws {
        let outcome = try await initialize(
            own: [own(state(request: "r1"), expiry: 500), junk(expiry: .max)],
            peer: []
        )

        let success = try #require(outcome.success)
        #expect(success.priority == 501)
    }

    @Test func junkNewerThanTheRealStateDoesNotShadowIt() async throws {
        let outcome = try await initialize(
            own: [own(state(request: "r1"), expiry: 500), junk(expiry: 900)],
            peer: []
        )

        let success = try #require(outcome.success)
        #expect(success.outgoingState.outgoingRequests[.device]?.requestId == "r1")
        #expect(success.outgoingState.initializedMessages == [TestMessage(id: 1)])
    }

    @Test func junkOnThePeerTopicKeepsThePeerRequestPending() async throws {
        let outcome = try await initialize(
            own: [],
            peer: [peer(state(request: "q1"), from: peerDeviceA, expiry: 400), junk(expiry: 900, from: peerDeviceA)]
        )

        let success = try #require(outcome.success)
        #expect(success.incomingState.peerRequests.map(\.request.requestId) == ["q1"])
    }

    @Test func ownAckIsRestoredAndMarksThePeerRequestHandled() async throws {
        let outcome = try await initialize(
            own: [own(state(response: "q1"), expiry: 500)],
            peer: [peer(state(request: "q1"), from: peerDeviceA, expiry: 400)]
        )

        let success = try #require(outcome.success)
        #expect(success.incomingState.peerRequests.isEmpty)
        #expect(success.ownStates[.device]?.response?.requestId == "q1")
    }

    @Test func ownRequestAckedByThePeerIsDeliveredOnRestore() async throws {
        let outcome = try await initialize(
            own: [own(state(request: "r1"), expiry: 500)],
            peer: [peer(state(response: "r1"), from: peerDeviceA, expiry: 400)]
        )

        let success = try #require(outcome.success)
        #expect(success.outgoingState.peerResponses[.device]?.requestId == "r1")
        #expect(success.outgoingState.outgoingRequests[.device]?.requestId == "r1")
        #expect(success.ownStates[.device]?.request?.requestId == "r1")
    }

    @Test func onlyTheLatestStateOfEachPeerDeviceCounts() async throws {
        let outcome = try await initialize(
            own: [],
            peer: [
                peer(state(request: "old"), from: peerDeviceA, expiry: 100),
                peer(state(request: "a2"), from: peerDeviceA, expiry: 200),
                peer(state(request: "b1"), from: peerDeviceB, expiry: 150)
            ]
        )

        let success = try #require(outcome.success)
        #expect(Set(success.incomingState.peerRequests.map(\.request.requestId)) == ["a2", "b1"])
    }

    @Test func unparsableStatementOnTheTopicDoesNotFailInitialization() async throws {
        let outcome = try await initialize(
            own: [],
            peer: [peer(state(request: "q1"), from: peerDeviceA, expiry: 400)],
            peerError: .statementDecodingFailed
        )

        let success = try #require(outcome.success)
        #expect(success.incomingState.peerRequests.map(\.request.requestId) == ["q1"])
    }

    @Test func pollingErrorFailsInitialization() async throws {
        let outcome = try await initialize(own: [], peer: [], peerError: .other(PollingFailure()))

        #expect(outcome.success == nil)
        #expect(outcome.failure != nil)
    }
}

private extension PeerSessionInitializerTests {
    func initialize(
        own: [PeerSessionStatement],
        peer: [PeerSessionStatement],
        peerError: StatementSubscriptionError? = nil
    ) async throws -> InitializerOutcome {
        let workQueue = DispatchQueue(label: "test.peer-session-initializer")
        let initializer = PeerSessionInitializer<TestMessage>(
            priorityProvider: PeerSessionPriorityProvider(priorityFactory: FixedPriorityFactory(), logger: nil),
            ownSubscription: FixedSubscription(statements: own),
            peerSubscription: FixedSubscription(statements: peer, error: peerError),
            workQueue: workQueue,
            statementDataCoder: coder,
            supportedRoutes: [.device],
            logger: nil
        )
        let recorder = InitializerRecorder()
        initializer.delegate = AnyPeerSessionInitializerDelegate(recorder)

        return await withCheckedContinuation { continuation in
            recorder.onOutcome = { continuation.resume(returning: $0) }
            initializer.initializeSession()
        }
    }

    func state(response: String? = nil, request: String? = nil) -> MessageExchange.SessionState<TestMessage> {
        MessageExchange.SessionState(
            response: response.map { MessageExchange.Response(requestId: $0, responseCode: .success) },
            request: request.map { .init(requestId: $0, messages: [TestMessage(id: 1)]) }
        )
    }

    func own(_ state: MessageExchange.SessionState<TestMessage>, expiry: UInt64) throws -> PeerSessionStatement {
        try statement(state, from: ownAccountId, expiry: expiry)
    }

    func peer(
        _ state: MessageExchange.SessionState<TestMessage>,
        from device: Data,
        expiry: UInt64
    ) throws -> PeerSessionStatement {
        try statement(state, from: device, expiry: expiry)
    }

    func statement(
        _ state: MessageExchange.SessionState<TestMessage>,
        from topicAccountId: Data,
        expiry: UInt64
    ) throws -> PeerSessionStatement {
        let payload = try coder.encodeToScaleEncodedPayload(StatementData.state(state), route: .device)
        return PeerSessionStatement(
            statement: [.expiry(expiry), .scaleEncodedPayload(payload)],
            route: .device,
            topicAccountId: topicAccountId
        )
    }

    /// What anyone can publish under a known topic: well-formed fields, but not encrypted with the session key.
    func junk(expiry: UInt64, from topicAccountId: Data? = nil) -> PeerSessionStatement {
        PeerSessionStatement(
            statement: [.expiry(expiry), .scaleEncodedPayload((try? Data(count: 64).scaleEncoded()) ?? Data())],
            route: .device,
            topicAccountId: topicAccountId ?? ownAccountId
        )
    }
}

struct InitializerOutcome {
    let success: SessionInitializationSuccess<TestMessage>?
    let failure: SessionInitializationFailure?
}

struct PollingFailure: Error {}

private final class InitializerRecorder: PeerSessionInitializerDelegate, TypeErasedDelegateStoring {
    var onOutcome: ((InitializerOutcome) -> Void)?

    func sessionInitializer(
        _: PeerSessionInitializing,
        didInitializeWith result: SessionInitializationSuccess<TestMessage>
    ) {
        onOutcome?(InitializerOutcome(success: result, failure: nil))
    }

    func sessionInitializer(
        _: PeerSessionInitializing,
        didFailToInitializeWith result: SessionInitializationFailure
    ) {
        onOutcome?(InitializerOutcome(success: nil, failure: result))
    }
}

private final class FixedSubscription: PeerSessionStatementSubscribing {
    let statements: [PeerSessionStatement]
    let error: StatementSubscriptionError?

    init(statements: [PeerSessionStatement], error: StatementSubscriptionError? = nil) {
        self.statements = statements
        self.error = error
    }

    func start(handler _: @escaping PeerSessionStatementHandler) {}
    func stop() {}
    func resetSeenHashes() {}

    func fetchOnce(
        handler: @escaping PeerSessionStatementHandler,
        completion: ((StatementSubscriptionError?) -> Void)?
    ) {
        statements.forEach { _ = handler($0) }
        completion?(error)
    }
}

final class FixedPriorityFactory: StatementPriorityMaking {
    func makeTimestampPriority() -> UInt64 { 100 }
}
