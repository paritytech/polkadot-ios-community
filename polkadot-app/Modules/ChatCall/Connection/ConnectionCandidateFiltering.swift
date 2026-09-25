import Foundation

/// Decides whether a local or remote ICE candidate should participate in connectivity checks.
/// Implementations are applied symmetrically: outgoing candidates are dropped before they
/// reach the signaling channel; incoming candidates are dropped before they enter the local
/// ICE agent. Pass-through (no filtering) is the default — callers opt in by injecting a
/// concrete filter.
protocol ConnectionCandidateFiltering {
    func shouldAccept(_ candidate: PeerConnectionCandidate) -> Bool
}

/// Drops candidates with TCP transport and `typ host`. They almost never succeed across
/// NAT (both peers would need to accept inbound TCP), yet on devices with many network
/// interfaces they make up ~50% of generated candidates and inflate ICE pair counts
/// quadratically.
struct TcpHostCandidateFilter: ConnectionCandidateFiltering {
    func shouldAccept(_ candidate: PeerConnectionCandidate) -> Bool {
        !candidate.isTCPHost
    }
}

/// Drops `typ host` candidates on private, link-local or loopback addresses.
///
/// Once Local Network access is denied, iOS closes any socket that sends to the local network —
/// and a reflexive candidate shares its per-interface socket with that interface's host
/// candidate, so probing a peer's LAN address can take the reflexive path down with it.
struct PrivateHostCandidateFilter: ConnectionCandidateFiltering {
    func shouldAccept(_ candidate: PeerConnectionCandidate) -> Bool {
        !candidate.isPrivateHost
    }
}

struct CompositeCandidateFilter: ConnectionCandidateFiltering {
    let filters: [ConnectionCandidateFiltering]

    init(_ filters: [ConnectionCandidateFiltering]) {
        self.filters = filters
    }

    func shouldAccept(_ candidate: PeerConnectionCandidate) -> Bool {
        filters.allSatisfy { $0.shouldAccept(candidate) }
    }
}
