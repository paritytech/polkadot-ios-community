import Foundation

protocol DeviceSyncFileChannelRegistering: Sendable {
    func register(_ requester: any DeviceSyncFileRequesting, connectionId: UUID) async
    func unregister(connectionId: UUID) async
}

protocol DeviceSyncFileChannelProviding: Sendable {
    /// The most recently opened channel to a sibling, if any is open.
    func openRequester() async -> (any DeviceSyncFileRequesting)?
}

/// Open `device-sync-file` channels, keyed by connection rather than peer account id:
/// installations restored from the same mnemonic share the account id.
actor DeviceSyncFileChannelRegistry {
    private var channels: [(connectionId: UUID, requester: any DeviceSyncFileRequesting)] = []
}

extension DeviceSyncFileChannelRegistry: DeviceSyncFileChannelRegistering {
    func register(_ requester: any DeviceSyncFileRequesting, connectionId: UUID) {
        channels.removeAll { $0.connectionId == connectionId }
        channels.append((connectionId, requester))
    }

    func unregister(connectionId: UUID) {
        channels.removeAll { $0.connectionId == connectionId }
    }
}

extension DeviceSyncFileChannelRegistry: DeviceSyncFileChannelProviding {
    func openRequester() -> (any DeviceSyncFileRequesting)? {
        channels.last?.requester
    }
}
