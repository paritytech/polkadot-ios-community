@testable import polkadot_app
import Foundation
import Testing
import WebRTC

@Suite("WebRTC data channel configuration")
struct WebRTCConfigFactoryTests {
    private let factory = WebRTCConfigFactory(turnService: UnusedTURNCredentials())

    @Test("a reliable channel is ordered and sets no retransmit limit")
    func reliableChannelHasNoLimit() {
        #expect(DataChannelReliability.reliable.maxRetransmits == nil)
        #expect(factory.makeDataChannelConfiguration(.reliable).isOrdered)
    }

    @Test("a best-effort channel keeps its retransmit limit")
    func bestEffortChannelKeepsRetransmitLimit() {
        let configuration = factory.makeDataChannelConfiguration(.bestEffort(maxRetransmits: 3))

        #expect(configuration.isOrdered)
        #expect(configuration.maxRetransmits == 3)
    }
}

private struct UnusedTURNCredentials: TURNCredentialsProviding {
    func issueCredentials() async throws -> TURNCredentials {
        throw URLError(.cancelled)
    }
}
