import Foundation

enum DeviceSyncFileWriterError: Error, Equatable {
    case unexpectedOffset(expected: UInt64, received: UInt64)
    case sizeMismatch(expected: UInt64, stored: UInt64)
}

/// Appends a file received from a sibling to `<filename>.sync.part` in the downloads store and moves it
/// under `filename` once complete. The suffix keeps it apart from the HOP `.part` resume state.
final class DeviceSyncFileWriter {
    static let partialSuffix = ".sync.part"

    let filename: String

    private let store: AttachmentStoring
    private let fileManager: FileManager
    private var handle: FileHandle?

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

        let handle = try openHandle()
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// Moves the partial file into place; on a size mismatch the partial file is discarded.
    func finish(totalSize: UInt64) throws {
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

        if totalSize == 0, !store.hasFile(for: partialFilename) {
            try store.createEmptyFile(for: partialFilename)
        }

        try store.moveFile(from: partialFilename, to: filename)
    }

    func discard() {
        closeHandle()

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
