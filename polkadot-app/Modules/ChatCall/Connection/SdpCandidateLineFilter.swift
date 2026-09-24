import Foundation

/// Applies a `ConnectionCandidateFiltering` to the `a=candidate` lines carried inside an offer
/// or answer, which never reach `handleRemoteCandidates` and so escape the usual filtering.
struct SdpCandidateLineFilter {
    private static let linePrefix = "a=candidate:"

    private let candidateFilter: ConnectionCandidateFiltering

    init(_ candidateFilter: ConnectionCandidateFiltering) {
        self.candidateFilter = candidateFilter
    }

    func apply(to sdp: String) -> String {
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        let lines = sdp.components(separatedBy: separator)
        let kept = lines.filter(shouldKeep)

        // Rebuilding an SDP nothing was dropped from risks normalising line endings for no gain.
        guard kept.count != lines.count else { return sdp }

        return kept.joined(separator: separator)
    }
}

private extension SdpCandidateLineFilter {
    func shouldKeep(_ line: String) -> Bool {
        guard line.hasPrefix(Self.linePrefix) else { return true }

        let candidate = PeerConnectionCandidate(
            sdp: String(line.dropFirst("a=".count)),
            sdpMLineIndex: 0,
            sdpMid: "0"
        )

        return candidateFilter.shouldAccept(candidate)
    }
}
