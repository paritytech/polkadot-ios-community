import Foundation
import WebRTC

protocol WebRTCConfigMaking: Sendable {
    func makeConnectionConfiguration() async throws -> RTCConfiguration
    func makeDataChannelConfiguration() -> RTCDataChannelConfiguration
}

final class WebRTCConfigFactory: WebRTCConfigMaking {
    private let turnService: TURNCredentialsProviding
    private let iceCandidatePoolSize: Int32
    private let iceTransportPolicy: RTCIceTransportPolicy

    init(
        turnService: TURNCredentialsProviding,
        iceCandidatePoolSize: Int32 = 8,
        iceTransportPolicy: RTCIceTransportPolicy = .all
    ) {
        self.turnService = turnService
        self.iceCandidatePoolSize = iceCandidatePoolSize
        self.iceTransportPolicy = iceTransportPolicy
    }

    func makeConnectionConfiguration() async throws -> RTCConfiguration {
        let credentials = try await turnService.issueCredentials()

        let configuration = RTCConfiguration()
        configuration.iceServers = makeIceServers(from: credentials)
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceCandidatePoolSize = iceCandidatePoolSize
        // Calls pass `.noHost`: srflx and relay are still gathered, but host candidates
        // are suppressed, so a call never advertises a local-network address.
        configuration.iceTransportPolicy = iceTransportPolicy
        // recommended by WebRTC team to avoid complexity explosion
        configuration.maxIPv6Networks = 1

        return configuration
    }

    func makeDataChannelConfiguration() -> RTCDataChannelConfiguration {
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        dataChannelConfig.maxRetransmits = 3
        dataChannelConfig.isNegotiated = false

        return dataChannelConfig
    }
}

private extension WebRTCConfigFactory {
    func makeIceServers(from credentials: TURNCredentials) -> [RTCIceServer] {
        var result: [RTCIceServer] = []

        if !credentials.stunUrls.isEmpty {
            result.append(RTCIceServer(urlStrings: credentials.stunUrls))
        }

        if !credentials.turnUrls.isEmpty {
            result.append(
                RTCIceServer(
                    urlStrings: credentials.turnUrls,
                    username: credentials.username,
                    credential: credentials.password
                )
            )
        }

        return result
    }
}
