import Foundation
import WebRTC

protocol WebRTCConfigMaking: Sendable {
    func makeConnectionConfiguration() async throws -> RTCConfiguration
    func makeDataChannelConfiguration() -> RTCDataChannelConfiguration
}

final class WebRTCConfigFactory: WebRTCConfigMaking {
    private let turnService: TURNCredentialsProviding

    init(turnService: TURNCredentialsProviding) {
        self.turnService = turnService
    }

    func makeConnectionConfiguration() async throws -> RTCConfiguration {
        let credentials = try await turnService.issueCredentials()

        let configuration = RTCConfiguration()
        configuration.iceServers = makeIceServers(from: credentials)
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceCandidatePoolSize = 8
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
