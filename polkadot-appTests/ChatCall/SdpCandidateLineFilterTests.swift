@testable import polkadot_app
import Foundation
import Testing

/// Candidates carried inside an offer or answer never reach `handleRemoteCandidates`, so the same
/// filter is applied to the SDP text before it becomes the remote description.
struct SdpCandidateLineFilterTests {
    private let sut = SdpCandidateLineFilter(PrivateHostCandidateFilter())

    private static let privateHost = "a=candidate:1 1 UDP 2130706431 192.168.1.100 54321 typ host"
    private static let publicHost = "a=candidate:2 1 UDP 2130706430 2001:db8::1 12345 typ host"
    private static let reflexive =
        "a=candidate:3 1 UDP 1694498815 8.8.8.8 3478 typ srflx raddr 192.168.1.100 rport 54321"

    @Test("drops the lines the candidate filter rejects and keeps everything else in order")
    func dropsRejectedLines() {
        let sdp = [
            "v=0",
            "m=audio 9 UDP/TLS/RTP/SAVPF 111",
            Self.privateHost,
            Self.reflexive,
            Self.publicHost,
            "a=end-of-candidates"
        ]
        .joined(separator: "\r\n")

        let filtered = sut.apply(to: sdp)

        #expect(filtered.components(separatedBy: "\r\n") == [
            "v=0",
            "m=audio 9 UDP/TLS/RTP/SAVPF 111",
            Self.reflexive,
            Self.publicHost,
            "a=end-of-candidates"
        ])
    }

    @Test("keeps a candidate line it cannot parse")
    func keepsUnparsableLines() {
        let sdp = ["a=candidate:garbage", Self.reflexive].joined(separator: "\r\n")

        #expect(sut.apply(to: sdp) == sdp)
    }

    @Test("leaves an SDP without candidates untouched, whatever its line ending")
    func leavesOtherSdpsAlone() {
        let sdp = "v=0\no=- 1 1 IN IP4 127.0.0.1\n"

        #expect(sut.apply(to: sdp) == sdp)
    }
}
