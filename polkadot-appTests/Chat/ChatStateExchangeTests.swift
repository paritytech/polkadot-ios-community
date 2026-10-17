@testable import polkadot_app
import CryptoKit
import Foundation
import MessageExchangeKit
import NovaCrypto
import os
import StatementStore
import SubstrateSdk
import Testing

/// End to end over a store that replaces a signer's statement per channel, as the real one does.
@Suite(.timeLimit(.minutes(1)))
struct ChatStateExchangeTests {
    let store = MockStatementStore(replacesByChannel: true)
    let events = ChatEventLog()
    let alice: ChatIdentity
    let bob: ChatIdentity

    init() throws {
        alice = try ChatIdentity(name: "alice")
        bob = try ChatIdentity(name: "bob")
    }

    @Test(arguments: ChatMode.allCases)
    func simultaneousSendsAreBothDelivered(mode: ChatMode) async throws {
        let (aliceChat, bobChat) = try connect(mode: mode)

        aliceChat.send("a1")
        bobChat.send("b1")

        try await events.waitFor(.received("a1", by: "bob"), .received("b1", by: "alice"))
        try await events.waitFor(.delivered("a1", by: "alice"), .delivered("b1", by: "bob"))
    }

    @Test(arguments: ChatMode.allCases)
    func eachParticipantKeepsOneLiveStatementOnItsTopic(mode: ChatMode) async throws {
        let (aliceChat, bobChat) = try connect(mode: mode)

        aliceChat.send("a1")
        try await events.waitFor(.delivered("a1", by: "alice"))
        bobChat.send("b1")
        try await events.waitFor(.delivered("b1", by: "bob"))

        let senders = try store.allStatements().compactMap { $0.getSenderAccountId() }
        #expect(senders.count == 2)
        #expect(Set(senders) == [alice.accountId, bob.accountId])
    }

    @Test(arguments: ChatMode.allCases)
    func ackOnlyAndMessageStatementsHaveEqualPayloadSize(mode: ChatMode) async throws {
        let (aliceChat, bobChat) = try connect(mode: mode)

        aliceChat.send("a1")
        try await events.waitFor(.delivered("a1", by: "alice"))

        let payloadSizes = try store.allStatements().compactMap { $0.getScaleEncodedPayload()?.count }
        #expect(payloadSizes.count == 2)
        #expect(Set(payloadSizes).count == 1)
        withExtendedLifetime(bobChat) {}
    }

    @Test(arguments: ChatMode.allCases)
    func restartKeepsTheAckSoTheMessageIsNotRedelivered(mode: ChatMode) async throws {
        let (aliceChat, bobChat) = try connect(mode: mode)

        aliceChat.send("a1")
        try await events.waitFor(.delivered("a1", by: "alice"))

        bobChat.disconnect()
        let restartedBob = try endpoint(bob, talkingTo: alice, mode: mode)
        aliceChat.send("a2")
        try await events.waitFor(.received("a2", by: "bob"))

        #expect(events.count(of: .received("a1", by: "bob")) == 1)
        withExtendedLifetime(restartedBob) {}
    }

    @Test(arguments: ChatMode.allCases)
    func junkWithMaxExpiryOnOurTopicDoesNotBlockTheSession(mode: ChatMode) async throws {
        let (aliceChat, bobChat) = try connect(mode: mode)

        aliceChat.send("a1")
        try await events.waitFor(.delivered("a1", by: "alice"))
        try postJunk(onTopicOf: alice.accountId)

        aliceChat.disconnect()
        let restartedAlice = try endpoint(alice, talkingTo: bob, mode: mode)
        restartedAlice.send("a2")

        try await events.waitFor(.received("a2", by: "bob"), .delivered("a2", by: "alice"))
        withExtendedLifetime(bobChat) {}
    }

    @Test func envelopeForSeveralPeerDevicesStaysAtTheSmallestBucket() async throws {
        let bobDesktop = try MessageExchange.DeviceInfo(
            statementAccountId: Data.randomOrError(of: 32),
            encryptionPublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        )
        let aliceChat = try ChatEndpoint(
            identity: alice,
            peer: bob,
            mode: .multidevice,
            extraPeerDevices: [bobDesktop],
            store: store,
            events: events
        )
        let bobChat = try endpoint(bob, talkingTo: alice, mode: .multidevice)

        aliceChat.send("a1")
        try await events.waitFor(.received("a1", by: "bob"), .delivered("a1", by: "alice"))

        let payloadSizes = try store.allStatements().compactMap { $0.getScaleEncodedPayload()?.count }
        #expect(payloadSizes.count == 2)
        #expect(Set(payloadSizes).count == 1)
        withExtendedLifetime(bobChat) {}
    }
}

private extension ChatStateExchangeTests {
    func connect(mode: ChatMode) throws -> (ChatEndpoint, ChatEndpoint) {
        try (endpoint(alice, talkingTo: bob, mode: mode), endpoint(bob, talkingTo: alice, mode: mode))
    }

    func endpoint(_ identity: ChatIdentity, talkingTo peer: ChatIdentity, mode: ChatMode) throws -> ChatEndpoint {
        try ChatEndpoint(identity: identity, peer: peer, mode: mode, store: store, events: events)
    }

    /// What anyone who saw the topic can publish: a validly signed statement that isn't encrypted for the session.
    func postJunk(onTopicOf accountId: AccountId) throws {
        let topic = try #require(
            store.allStatements().first { $0.getSenderAccountId() == accountId }?.getTopic1()
        )
        let stranger = try SNKeyFactory().createKeypair(fromSeed: Data.randomOrError(of: 32))
        let junk = try UnsignedStatement()
            .addTopic1(topic)
            .addChannel(Data(repeating: 0xAB, count: 32))
            .addExpiry(.max)
            .addScaleEncodedPayload(Data(repeating: 0xCD, count: 64).scaleEncoded())
            .signed(by: StatementStoreKeypairSigner(keypair: stranger))

        try store.insertStatement(with: junk)
    }
}

// MARK: - Harness

enum ChatMode: CaseIterable, Sendable {
    case identity
    case multidevice
}

struct ChatIdentity {
    let name: String
    let keypair: SNKeypairProtocol
    let encryptionKey = Curve25519.KeyAgreement.PrivateKey()
    let deviceEncryptionKey = Curve25519.KeyAgreement.PrivateKey()

    var accountId: AccountId { keypair.publicKey().rawData() }

    init(name: String) throws {
        self.name = name
        keypair = try SNKeyFactory().createKeypair(fromSeed: Data.randomOrError(of: 32))
    }

    /// The identity account doubles as the device's statement account.
    var device: MessageExchange.DeviceInfo {
        .init(statementAccountId: accountId, encryptionPublicKey: deviceEncryptionKey.publicKey.rawRepresentation)
    }
}

final class ChatEndpoint {
    private let participant = MockChatParticipant()
    private let service: AnyMessageExchangeService<Chat.OpaqueMessage>
    private let peer: MessageExchange.Peer

    init(
        identity: ChatIdentity,
        peer: ChatIdentity,
        mode: ChatMode,
        extraPeerDevices: [MessageExchange.DeviceInfo] = [],
        store: MockStatementStore,
        events: ChatEventLog
    ) throws {
        self.peer = MessageExchange.Peer(
            accountId: peer.accountId,
            publicKey: peer.encryptionKey.publicKey.rawRepresentation,
            pin: nil,
            devices: mode == .multidevice ? [peer.device] + extraPeerDevices : []
        )
        service = try Self.makeService(identity: identity, mode: mode, store: store, delegate: participant)

        let name = identity.name
        participant.didReceiveMessagesClosure = { _, messages, completion in
            messages.forEach { events.record(.received($0.remoteMessage.messageId, by: name)) }
            completion(.success)
        }
        participant.didDeliverMessagesClosure = { _, messages, error in
            guard error == nil else { return }
            messages.forEach { events.record(.delivered($0.remoteMessage.messageId, by: name)) }
        }

        service.updateSessions([
            MessageExchange.SessionRequest(own: .init(signKeyId: "", encryptionKeyId: "", pin: nil), peer: self.peer)
        ])
    }

    func send(_ messageId: String) {
        let message = Chat.RemoteMessage(
            messageId: messageId,
            timestamp: Date().toChatTimestamp(),
            versioned: .v1(.init(content: .text("message \(messageId)")))
        )
        service.addMessagesToQueue([.init(remoteMessage: message)], for: peer)
    }

    func disconnect() {
        service.updateSessions([])
    }

    private static func makeService(
        identity: ChatIdentity,
        mode: ChatMode,
        store: MockStatementStore,
        delegate: MockChatParticipant
    ) throws -> AnyMessageExchangeService<Chat.OpaqueMessage> {
        let signManager = ClosureSignerManager { _ in StatementStoreKeypairSigner(keypair: identity.keypair) }
        let encryptionKey = identity.encryptionKey
        let encryptionManager = ClosureEncryptionManager { _ in
            X25519ChaChaPolyEncryptorFactory(privateKey: encryptionKey)
        }

        return try MessageExchangeServiceFactory(
            messageExchangeModeProvider: FixedMessageExchangeModeProvider(
                mode: mode == .multidevice ? .multidevice : .identity
            ),
            signManager: signManager,
            encryptionManager: encryptionManager,
            deviceEncryptionKeyFactory: mode == .multidevice
                ? X25519ChaChaPolyEncryptorFactory(privateKey: identity.deviceEncryptionKey)
                : nil,
            maxStatementSize: 500 * 1_024
        ).makeService(
            statementStoreConnection: store,
            statementSignerResolver: IdentitySignerResolver(signManager: signManager),
            delegate: AnyPeerSessionDelegate(delegate)
        )
    }
}

final class ChatEventLog: @unchecked Sendable {
    struct Event: Hashable {
        let kind: String
        let messageId: String
        let participant: String

        static func received(_ messageId: String, by participant: String) -> Event {
            Event(kind: "received", messageId: messageId, participant: participant)
        }

        static func delivered(_ messageId: String, by participant: String) -> Event {
            Event(kind: "delivered", messageId: messageId, participant: participant)
        }
    }

    private struct State {
        var events: [Event] = []
        var waiters: [(Set<Event>, CheckedContinuation<Void, Never>)] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func record(_ event: Event) {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.events.append(event)
            let recorded = Set(state.events)
            let ready = state.waiters.filter { $0.0.isSubset(of: recorded) }.map(\.1)
            state.waiters.removeAll { $0.0.isSubset(of: recorded) }
            return ready
        }

        ready.forEach { $0.resume() }
    }

    func count(of event: Event) -> Int {
        state.withLock { $0.events.filter { $0 == event }.count }
    }

    func waitFor(_ expected: Event...) async throws {
        let expected = Set(expected)

        await withCheckedContinuation { continuation in
            let isReady = state.withLock { state -> Bool in
                guard !expected.isSubset(of: Set(state.events)) else { return true }
                state.waiters.append((expected, continuation))
                return false
            }

            if isReady {
                continuation.resume()
            }
        }
    }
}
