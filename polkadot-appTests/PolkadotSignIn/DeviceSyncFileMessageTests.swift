@testable import polkadot_app
import Foundation
import SubstrateSdk
import SubstrateSdkExt
import Testing

/// Byte-level pins for the `device-sync-file` wire format (File Transfer RFC §2).
/// Desktop has no implementation yet, so the vectors are derived from the spec layout.
@Suite("DeviceSyncFileMessage Coding Tests")
struct DeviceSyncFileMessageTests {
    typealias Message = Chat.DeviceSyncFileMessage

    private static let attachment = Message.FileReference.messageAttachment(
        .init(messageId: "m1", identifier: Data([0xAA, 0xBB]))
    )

    // u8 tag 0 · String "m1" (compact len 2) · ByteArray [aa bb] (compact len 2)
    private static let attachmentHex = "00" + "086d31" + "08aabb"

    @Test(
        "Every case encodes with its RFC index and field layout",
        arguments: [
            (
                Message.filesRequest(.init(requestId: 7, files: [.init(file: attachment, offset: 4_096)])),
                "00" + "07000000" + "04" + attachmentHex + "0010000000000000"
            ),
            (
                Message.header(.init(requestId: 7, fileIndex: 2, totalSize: 300)),
                "01" + "07000000" + "02000000" + "2c01000000000000"
            ),
            (
                Message.chunk(.init(requestId: 7, fileIndex: 0, offset: 4_096, data: Data([1, 2, 3]))),
                "02" + "07000000" + "00000000" + "0010000000000000" + "0c010203"
            ),
            (
                Message.unavailable(.init(requestId: 7, fileIndex: 1, reason: .downloading)),
                "03" + "07000000" + "01000000" + "01"
            ),
            (Message.cancelFilesRequest(requestId: 7), "04" + "07000000"),
            (Message.completed(requestId: 7), "05" + "07000000"),
            (
                Message.availabilityRequest(.init(requestId: 9, files: [attachment])),
                "06" + "09000000" + "04" + attachmentHex
            ),
            (
                Message.availabilityResponse(
                    .init(requestId: 9, availability: [.available(totalSize: 300), .unavailable(.notStored)])
                ),
                "07" + "09000000" + "08" + "002c01000000000000" + "0100"
            )
        ]
    )
    func scaleLayout(message: Message, hex: String) throws {
        let bytes = try hex.fromHex()

        #expect(try message.scaleEncoded() == bytes)
        #expect(try Message.fromScaleEncoded(bytes) == message)
    }

    @Test(
        "Unknown enum indices fail to decode",
        arguments: [
            "08" + "07000000",
            "03" + "07000000" + "01000000" + "02",
            "00" + "07000000" + "04" + "01086d3108aabb" + "0000000000000000",
            "07" + "09000000" + "04" + "02"
        ]
    )
    func unknownIndexThrows(hex: String) throws {
        let bytes = try hex.fromHex()

        #expect(throws: (any Error).self) {
            try Message.fromScaleEncoded(bytes)
        }
    }

    @Test("A 60 KiB chunk in its data channel envelope stays under the 64 KiB SCTP limit")
    func fullChunkFitsDataChannelMessage() throws {
        let chunkPayloadSize = 60 * 1_024
        let sctpMaxMessageSize = 64 * 1_024
        let chunk = try Message.chunk(
            .init(
                requestId: .max,
                fileIndex: .max,
                offset: .max,
                data: Data.randomOrError(of: chunkPayloadSize)
            )
        )
        let envelope = try DataChannelMessage(id: "device-sync-file", data: chunk.scaleEncoded())

        #expect(try envelope.scaleEncoded().count < sctpMaxMessageSize)
    }
}
