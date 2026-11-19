import CryptoKit
import Foundation

enum DeviceSyncFileWriterError: Error, Equatable {
    case unexpectedOffset(expected: UInt64, received: UInt64)
    case sizeMismatch(expected: UInt64, stored: UInt64)
    case hashMismatch
}

/// Appends a file received from a sibling to `<filename>.sync.part` in the downloads store and moves it
/// under `filename` once complete. The suffix keeps it apart from the HOP `.part` resume state.
final class DeviceSyncFileWriter {
    static let partialSuffix = ".sync.part"
    static let replayReadSize = 1 << 20

    let filename: String

    private let store: AttachmentStoring
    private let fileManager: FileManager
    private var handle: FileHandle?
    private var hasher = SHA256()
    private var hashedBytes: UInt64 = 0

    init(filename: String, store: AttachmentStoring, fileManager: FileManager = .default) {
        self.filename = filename
        self.store = store
        self.fileManager = fileManager
    }

    deinit {
        try? handle?.close()
    }

    var partialFilename: String {
        filename + Self.partialSuffix
    }

    func storedBytes() -> UInt64 {
        let url = store.fileURL(for: partialFilename)
        let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.uint64Value ?? 0
    }

    func write(_ data: Data, at offset: UInt64) throws {
        let stored = storedBytes()

        guard offset == stored else {
            throw DeviceSyncFileWriterError.unexpectedOffset(expected: stored, received: offset)
        }

        try hashStoredBytes(upTo: stored)
        let handle = try openHandle()
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        hasher.update(data: data)
        hashedBytes += UInt64(data.count)
    }

    /// Moves the partial file into place; a size or digest mismatch discards it.
    func finish(totalSize: UInt64, hash: Data) throws {
        closeHandle()

        guard !store.hasFile(for: filename) else {
            discard()
            return
        }

        let stored = storedBytes()

        guard stored == totalSize else {
            discard()
            throw DeviceSyncFileWriterError.sizeMismatch(expected: totalSize, stored: stored)
        }

        try hashStoredBytes(upTo: stored)
        guard Data(hasher.finalize()) == hash else {
            discard()
            throw DeviceSyncFileWriterError.hashMismatch
        }

        if totalSize == 0, !store.hasFile(for: partialFilename) {
            try store.createEmptyFile(for: partialFilename)
        }

        try store.moveFile(from: partialFilename, to: filename)
    }

    func discard() {
        closeHandle()
        hasher = SHA256()
        hashedBytes = 0

        if store.hasFile(for: partialFilename) {
            try? store.remove(for: partialFilename)
        }
    }

    func closeHandle() {
        try? handle?.close()
        handle = nil
    }
}

private extension DeviceSyncFileWriter {
    /// Bytes stored by an earlier connection never went through this hasher.
    func hashStoredBytes(upTo stored: UInt64) throws {
        guard hashedBytes < stored else { return }

        let reader = try FileHandle(forReadingFrom: store.fileURL(for: partialFilename))
        defer { try? reader.close() }
        try reader.seek(toOffset: hashedBytes)

        while hashedBytes < stored,
              let data = try reader.read(upToCount: Int(min(stored - hashedBytes, UInt64(Self.replayReadSize)))),
              !data.isEmpty {
            hasher.update(data: data)
            hashedBytes += UInt64(data.count)
        }
    }

    func openHandle() throws -> FileHandle {
        if let handle {
            return handle
        }

        if !store.hasFile(for: partialFilename) {
            try store.createEmptyFile(for: partialFilename)
        }

        let handle = try FileHandle(forWritingTo: store.fileURL(for: partialFilename))
        self.handle = handle
        return handle
    }
}
