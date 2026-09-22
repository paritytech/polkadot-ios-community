@testable import polkadot_app
import Foundation
import Testing

/// Covers the candidate filters that keep calls off the local network.
///
/// Uses the real `SdpCoder` tokenizer through `SdpCoderTests`' candidate fixtures, so the
/// filters and the encoding pipeline stay tested against one parser.
struct PrivateHostCandidateFilterTests {
    let sut = PrivateHostCandidateFilter()

    @Test(
        "Drops host candidates on private, link-local and loopback IPv4 addresses",
        arguments: [
            "10.0.0.1",
            "10.255.255.254",
            "172.16.0.1",
            "172.31.255.254",
            "192.168.1.100",
            "169.254.1.1",
            "127.0.0.1"
        ]
    )
    func dropsPrivateIPv4Host(ip: String) {
        let candidate = SdpCoderTests.makeIPv4Candidate(ip: ip, type: "host")

        #expect(!sut.shouldAccept(candidate))
    }

    /// `172.16/12` spans 172.16 through 172.31 only. A string-prefix implementation would
    /// wrongly drop every `172.*` address, so the neighbours of the range are the cases
    /// that actually discriminate a correct implementation from a plausible one.
    @Test(
        "Keeps host candidates on public addresses just outside 172.16/12",
        arguments: ["172.15.255.255", "172.32.0.1", "172.1.2.3", "8.8.8.8", "1.1.1.1"]
    )
    func keepsPublicIPv4Host(ip: String) {
        let candidate = SdpCoderTests.makeIPv4Candidate(ip: ip, type: "host")

        #expect(sut.shouldAccept(candidate))
    }

    @Test(
        "Drops host candidates on unique-local, link-local and loopback IPv6 addresses",
        arguments: ["fc00::1", "fd12:3456::1", "fe80::1", "::1"]
    )
    func dropsPrivateIPv6Host(ip: String) {
        let candidate = SdpCoderTests.makeIPv6Candidate(ip: ip, type: "host")

        #expect(!sut.shouldAccept(candidate))
    }

    /// iOS hands out globally-routable IPv6 host addresses on cellular. Those never touch
    /// the local network, so dropping them would remove a working direct path for nothing.
    @Test(
        "Keeps host candidates on globally-routable IPv6 addresses",
        arguments: ["2001:db8::1", "2a00:1450:4001::1"]
    )
    func keepsPublicIPv6Host(ip: String) {
        let candidate = SdpCoderTests.makeIPv6Candidate(ip: ip, type: "host")

        #expect(sut.shouldAccept(candidate))
    }

    /// Only `typ host` reaches a local address directly. A reflexive or relay candidate
    /// carrying a private address is still reached through the server, so it must survive.
    @Test("Keeps non-host candidates regardless of address", arguments: ["srflx", "relay", "prflx"])
    func keepsNonHostCandidates(type: String) {
        let candidate = SdpCoderTests.makeIPv4Candidate(ip: "192.168.1.100", type: type)

        #expect(sut.shouldAccept(candidate))
    }

    @Test("Keeps malformed candidates, matching isTCPHost")
    func keepsMalformedCandidate() {
        let candidate = PeerConnectionCandidate(sdp: "not-a-candidate", sdpMLineIndex: 0, sdpMid: "0")

        #expect(sut.shouldAccept(candidate))
    }
}

struct CompositeCandidateFilterTests {
    let sut = CompositeCandidateFilter([TcpHostCandidateFilter(), PrivateHostCandidateFilter()])

    @Test("Rejects when any child filter rejects")
    func rejectsWhenAnyChildRejects() {
        let tcpPublicHost = SdpCoderTests.makeIPv4Candidate(transport: "TCP", ip: "8.8.8.8", type: "host")
        let udpPrivateHost = SdpCoderTests.makeIPv4Candidate(transport: "UDP", ip: "192.168.1.100", type: "host")

        #expect(!sut.shouldAccept(tcpPublicHost))
        #expect(!sut.shouldAccept(udpPrivateHost))
    }

    @Test("Accepts only when every child filter accepts")
    func acceptsWhenAllChildrenAccept() {
        let udpPublicSrflx = SdpCoderTests.makeIPv4Candidate(transport: "UDP", ip: "8.8.8.8", type: "srflx")

        #expect(sut.shouldAccept(udpPublicSrflx))
    }

    @Test("Accepts everything when composed of no filters")
    func emptyCompositionAcceptsAll() {
        let empty = CompositeCandidateFilter([])
        let privateHost = SdpCoderTests.makeIPv4Candidate(ip: "192.168.1.100", type: "host")

        #expect(empty.shouldAccept(privateHost))
    }
}
