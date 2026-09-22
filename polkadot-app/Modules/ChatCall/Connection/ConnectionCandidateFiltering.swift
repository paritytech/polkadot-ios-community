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
/// iOS closes any socket that sends to the local network once Local Network access is
/// denied. A server-reflexive candidate is derived from the same per-interface UDP socket
/// as that interface's host candidate, so probing a peer's LAN address can take the
/// reflexive path down with it and leave TURN as the only route — or fail ICE outright.
/// Dropping these candidates symmetrically means a call never sends to a local address,
/// so the permission stops mattering and its prompt never appears.
struct PrivateHostCandidateFilter: ConnectionCandidateFiltering {
    func shouldAccept(_ candidate: PeerConnectionCandidate) -> Bool {
        !candidate.isPrivateHost
    }
}

/// Accepts a candidate only when every child filter accepts it, so each consumer composes
/// the policies it needs without the filters knowing about one another.
struct CompositeCandidateFilter: ConnectionCandidateFiltering {
    let filters: [ConnectionCandidateFiltering]

    init(_ filters: [ConnectionCandidateFiltering]) {
        self.filters = filters
    }

    func shouldAccept(_ candidate: PeerConnectionCandidate) -> Bool {
        filters.allSatisfy { $0.shouldAccept(candidate) }
    }
}
