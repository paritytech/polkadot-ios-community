@testable import polkadot_app
import Foundation
import SubstrateSdkExt
import Testing

/// Test vectors from the Device Transfer RFC (chat-spec feature/handoff b89ef95, Testing section).
struct DeviceTransferKeyScheduleTests {
    private static let entropyHex = "0x000102030405060708090a0b0c0d0e0f"
    private static let requestId = "6f1c2a9e-3b4d-4e5f-8a7b-0c1d2e3f4a5b"

    @Test("Entropy-derived keys match the RFC test vectors")
    func entropyKeysMatchVectors() throws {
        let schedule = try makeSchedule()
        let derived: [(String, Data, String)] = [
            (
                "transfer_seed",
                schedule.transferSeed,
                "1268901b5cfb153e286c4f07e30566b4ed7d0de53e2aa18cb5bd1e8741df1865"
            ),
            (
                "transfer_sender",
                schedule.senderLabel,
                "c698eeb293f2520a130d9ec22c68ae5359ec1b92df0523fba4bbae0471129746"
            ),
            (
                "transfer_receiver",
                schedule.receiverLabel,
                "78e71f96a97df2279bb3ee3938fb329c71010bea54f34d265c5f5e97bf629b4f"
            ),
            (
                "request_topic",
                schedule.requestTopic,
                "259721d79610866b25e13e8fbd8510fee77afa17ee7c550ca37b8c8beb6c25db"
            ),
            ("k_req", schedule.requestKey, "69261f4511e8ff2663af1f34d7ca99fb59df16f52fd1c1615e0f920c88173e7e"),
            (
                "active_topic",
                schedule.activeDeviceTopic,
                "083ddfa0ed96eeb898535425fd7525843fead54f834d03de5daba6cda72aad7c"
            ),
            ("k_active", schedule.activeKey, "a3b0345e394e7a92291c7613ad694c1751d93def13041301180d41e43af5731b")
        ]

        for (name, value, expectedHex) in derived {
            #expect(value.toHex() == expectedHex, "\(name)")
        }
    }

    @Test(
        "The session key matches the RFC vector whatever the request id's letter case",
        arguments: [requestId, requestId.uppercased()]
    )
    func sessionKeyMatchesVector(requestId: String) throws {
        let sessionKey = try makeSchedule().sessionKey(requestId: requestId)

        #expect(sessionKey.toHex() == "4a631c9f4173513c97cfd490250313bca445e4ae24347712b50d9954913c80bf")
    }

    @Test("The factory derives the schedule from the stored root entropy")
    func factoryUsesRootEntropy() throws {
        let entropy = try Self.entropyHex.fromHex()
        let factory = DeviceTransferKeyScheduleFactory(entropyManager: FixedRootEntropyManager(entropy: entropy))

        #expect(try factory.makeKeySchedule() == makeSchedule())
    }
}

private extension DeviceTransferKeyScheduleTests {
    func makeSchedule() throws -> DeviceTransferKeySchedule {
        try DeviceTransferKeySchedule(entropy: Self.entropyHex.fromHex())
    }
}
