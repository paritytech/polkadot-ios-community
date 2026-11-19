import Foundation
import WebRTC

/// Best effort skips a message once its retransmissions run out, which a file stream can't survive.
enum DataChannelReliability: Equatable, Sendable {
    case bestEffort(maxRetransmits: Int32)
    case reliable

    /// Read from here, not the configuration: WebRTC's getter aborts on an unset limit.
    var maxRetransmits: Int32? {
        switch self {
        case let .bestEffort(maxRetransmits): maxRetransmits
        case .reliable: nil
        }
    }
}

protocol WebRTCConfigMaking: Sendable {
    func makeConnectionConfiguration() async throws -> RTCConfiguration
    func makeDataChannelConfiguration(_ reliability: DataChannelReliability) -> RTCDataChannelConfiguration
}

final class WebRTCConfigFactory: WebRTCConfigMaking {
    private let turnService: TURNCredentialsProviding
    private let iceCandidatePoolSize: Int32

    init(turnService: TURNCredentialsProviding, iceCandidatePoolSize: Int32 = 8) {
        self.turnService = turnService
        self.iceCandidatePoolSize = iceCandidatePoolSize
    }

    func makeConnectionConfiguration() async throws -> RTCConfiguration {
        let credentials = try await turnService.issueCredentials()

        let configuration = RTCConfiguration()
        configuration.iceServers = makeIceServers(from: credentials)
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceCandidatePoolSize = iceCandidatePoolSize
        // recommended by WebRTC team to avoid complexity explosion
        configuration.maxIPv6Networks = 1

        return configuration
    }

    func makeDataChannelConfiguration(_ reliability: DataChannelReliability) -> RTCDataChannelConfiguration {
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        dataChannelConfig.isNegotiated = false

        if let maxRetransmits = reliability.maxRetransmits {
            dataChannelConfig.maxRetransmits = maxRetransmits
        }

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
