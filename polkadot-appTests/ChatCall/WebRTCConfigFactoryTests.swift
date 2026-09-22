@testable import polkadot_app
import Foundation
import Testing
import WebRTC

struct WebRTCConfigFactoryTests {
    /// DIM2 and device sync build their own factories and must keep gathering host
    /// candidates for local-network peers. Only calls opt out, so the default has to stay
    /// `.all` — a regression here would silently disable LAN discovery app-wide.
    @Test("Defaults to gathering every candidate type")
    func defaultsToAllTransports() async throws {
        let sut = WebRTCConfigFactory(turnService: StubTURNCredentialsService())

        let configuration = try await sut.makeConnectionConfiguration()

        #expect(configuration.iceTransportPolicy == .all)
    }

    @Test("Applies the requested transport policy")
    func appliesNoHostPolicy() async throws {
        let sut = WebRTCConfigFactory(
            turnService: StubTURNCredentialsService(),
            iceTransportPolicy: .noHost
        )

        let configuration = try await sut.makeConnectionConfiguration()

        #expect(configuration.iceTransportPolicy == .noHost)
    }

    @Test("Maps issued credentials onto STUN and TURN ice servers")
    func mapsCredentialsToIceServers() async throws {
        let sut = WebRTCConfigFactory(turnService: StubTURNCredentialsService())

        let configuration = try await sut.makeConnectionConfiguration()

        let allUrls = configuration.iceServers.flatMap(\.urlStrings)

        #expect(allUrls.contains("stun:stun.example.org:3478"))
        #expect(allUrls.contains("turn:turn.example.org:3478"))
    }
}
