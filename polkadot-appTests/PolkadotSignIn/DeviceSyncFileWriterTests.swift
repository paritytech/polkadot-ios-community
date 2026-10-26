@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

final class DeviceSyncFileWriterTests {
    private let directory: URL
    private let store: AttachmentStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceSyncFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        store = AttachmentStore(baseDirectory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Contiguous chunks are appended to .sync.part and moved into place on finish")
    func finishMovesCompleteFile() throws {
        let contents = try Data.randomOrError(of: 300)
        let writer = DeviceSyncFileWriter(filename: "file.jpg", store: store)

        try writer.write(contents.prefix(100), at: 0)
        try writer.write(contents.suffix(from: 100), at: 100)
        try writer.finish(totalSize: 300)

        #expect(try store.loadAttachment(by: "file.jpg") == contents)
        #expect(!store.hasFile(for: "file.jpg.sync.part"))
    }

    @Test("A partial file from an earlier connection is resumed at its stored size")
    func resumesExistingPartial() throws {
        let contents = try Data.randomOrError(of: 50)
        try store.store(attachment: contents.prefix(20), filename: "file.jpg.sync.part")
        let writer = DeviceSyncFileWriter(filename: "file.jpg", store: store)

        #expect(writer.storedBytes() == 20)

        try writer.write(contents.suffix(from: 20), at: 20)
        try writer.finish(totalSize: 50)

        #expect(try store.loadAttachment(by: "file.jpg") == contents)
    }

    @Test("A chunk that doesn't continue the stored bytes is rejected")
    func rejectsGap() throws {
        let writer = DeviceSyncFileWriter(filename: "file.jpg", store: store)
        try writer.write(Data(count: 10), at: 0)

        #expect(throws: DeviceSyncFileWriterError.unexpectedOffset(expected: 10, received: 20)) {
            try writer.write(Data(count: 10), at: 20)
        }
        #expect(writer.storedBytes() == 10)
    }

    @Test("A size mismatch on finish discards the partial file")
    func sizeMismatchDiscards() throws {
        let writer = DeviceSyncFileWriter(filename: "file.jpg", store: store)
        try writer.write(Data(count: 10), at: 0)

        #expect(throws: DeviceSyncFileWriterError.sizeMismatch(expected: 11, stored: 10)) {
            try writer.finish(totalSize: 11)
        }
        #expect(!store.hasFile(for: "file.jpg.sync.part"))
        #expect(!store.hasFile(for: "file.jpg"))
    }

    @Test("A file that already arrived another way wins and the partial file is dropped")
    func existingFileWins() throws {
        let existing = try Data.randomOrError(of: 10)
        try store.store(attachment: existing, filename: "file.jpg")
        let writer = DeviceSyncFileWriter(filename: "file.jpg", store: store)
        try writer.write(Data(count: 10), at: 0)

        try writer.finish(totalSize: 10)

        #expect(try store.loadAttachment(by: "file.jpg") == existing)
        #expect(!store.hasFile(for: "file.jpg.sync.part"))
    }
}
