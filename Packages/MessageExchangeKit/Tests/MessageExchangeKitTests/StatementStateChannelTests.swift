import Foundation
import StatementStore
import SubstrateSdk
import Testing
@testable import MessageExchangeKit

struct StatementStateChannelTests {
    let alice = Data(repeating: 1, count: 32)
    let bob = Data(repeating: 2, count: 32)
    let sharedSecret = Data(repeating: 7, count: 32)

    @Test func channelIsKeyedWithTheSharedSecret() throws {
        let sessionId = try makeSessionId(own: alice, peer: bob)

        let channel = try stateChannel(for: sessionId)

        #expect(try channel == ((sessionId.own + Data("state".utf8)).blake2b32WithKey(sharedSecret)))
    }

    @Test func channelCannotBeRecomputedFromThePublicTopic() throws {
        let sessionId = try makeSessionId(own: alice, peer: bob)
        let topic = sessionId.own

        let channel = try stateChannel(for: sessionId)

        for label in ["state", "request", "response"] {
            #expect(try channel != (Data(label.utf8).blake2b32WithKey(topic)))
            #expect(try channel != ((topic + Data(label.utf8)).blake2b32()))
        }
    }

    @Test func peerCanDeriveTheChannelOfOurTopic() throws {
        let ours = try makeSessionId(own: alice, peer: bob)
        let peers = try makeSessionId(own: bob, peer: alice)

        #expect(peers.peer == ours.own)
        #expect(peers.channelKey == ours.channelKey)
        #expect(
            try (peers.peer + Data("state".utf8)).blake2b32WithKey(peers.channelKey) == stateChannel(for: ours)
        )
    }

    @Test func differentSecretGivesDifferentChannel() throws {
        let first = try makeSessionId(own: alice, peer: bob)
        let second = try makeSessionId(own: alice, peer: bob, sharedSecret: Data(repeating: 8, count: 32))

        #expect(try stateChannel(for: first) != stateChannel(for: second))
    }

    @Test func descriptionDoesNotRevealTheChannelKey() throws {
        let sessionId = try makeSessionId(own: alice, peer: bob)

        #expect(!String(describing: sessionId).contains(sharedSecret.toHex()))
        #expect(!String(reflecting: sessionId).contains(sharedSecret.toHex()))
    }
}

private extension StatementStateChannelTests {
    func makeSessionId(own: Data, peer: Data, sharedSecret: Data? = nil) throws -> MessageExchange.SessionId {
        try PeerSessionIdFactory().createSessionId(
            for: PeerSessionInit(
                ownAccountId: own,
                ownPin: nil,
                peerAccountId: peer,
                peerPin: nil,
                sharedSecret: sharedSecret ?? self.sharedSecret
            )
        )
    }

    func stateChannel(for sessionId: MessageExchange.SessionId) throws -> Data {
        try ChatStatementChannelFactory().createStateChannel(for: sessionId).fixedStatementFieldData()
    }
}
