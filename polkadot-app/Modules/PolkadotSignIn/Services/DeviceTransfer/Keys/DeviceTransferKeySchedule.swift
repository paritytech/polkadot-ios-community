import Foundation
import KeyDerivation
import SubstrateSdk

/// Device transfer secrets derived from the root entropy (Device Transfer RFC §2).
/// `khash(key, data)` is keyed BLAKE2b-256: `data.blake2b32WithKey(key)`.
struct DeviceTransferKeySchedule: Equatable {
    let transferSeed: Data
    /// Labels stand in for account ids in the session derivation; they never sign anything.
    let senderLabel: Data
    let receiverLabel: Data
    /// Also the channel of the transfer request statement.
    let requestTopic: Data
    let requestKey: Data
    /// Also the channel of the active installation record.
    let activeDeviceTopic: Data
    let activeKey: Data

    init(entropy: Data) throws {
        let transferSeed = try Self.khash(key: entropy, label: "deviceTransfer")

        self.transferSeed = transferSeed
        senderLabel = try Self.khash(key: transferSeed, label: "sender")
        receiverLabel = try Self.khash(key: transferSeed, label: "receiver")
        requestTopic = try Self.khash(key: transferSeed, label: "requestTopic")
        requestKey = try Self.khash(key: transferSeed, label: "requestKey")
        activeDeviceTopic = try Self.khash(key: entropy, label: "activeDeviceTopic")
        activeKey = try Self.khash(key: entropy, label: "activeDeviceEncryptionKey")
    }

    /// `k_s` for one transfer. The request id is hashed in lowercase hyphenated form, which `UUID().uuidString`
    /// doesn't produce, so both sides must agree on it here.
    func sessionKey(requestId: String) throws -> Data {
        try Self.khash(key: transferSeed, label: "deviceTransferSession" + requestId.lowercased())
    }
}

private extension DeviceTransferKeySchedule {
    static func khash(key: Data, label: String) throws -> Data {
        try Data(label.utf8).blake2b32WithKey(key)
    }
}

protocol DeviceTransferKeyScheduleMaking {
    func makeKeySchedule() throws -> DeviceTransferKeySchedule
}

struct DeviceTransferKeyScheduleFactory: DeviceTransferKeyScheduleMaking {
    let entropyManager: RootEntropyManaging

    func makeKeySchedule() throws -> DeviceTransferKeySchedule {
        try DeviceTransferKeySchedule(entropy: entropyManager.fetchRootEntropy())
    }
}
