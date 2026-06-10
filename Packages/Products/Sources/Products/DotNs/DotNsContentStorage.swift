import Foundation

public protocol DotNsContentStorageProtocol {
    func saveContent(contentHash: String, files: [String: Data]) throws
    func getContentDirectory(contentHash: String) -> URL?
    func contentExists(contentHash: String) -> Bool
    func deleteContent(contentHash: String) throws
    func hasFileEntry(contentHash: String, relativePath: String) -> Bool
    func loadContent(contentHash: String, relativePath: String) -> Data?
    func deleteAll() throws
    func chatEntrypointRelativePath() -> String
}

public final class DotNsContentStorage: DotNsContentStorageProtocol {
    private let baseDirectory: URL
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = appSupport.appendingPathComponent("DotNsContent")
    }

    // Stage into a temp location and atomically move it into place.
    // This guarantees getContentDirectory never observes a partially written
    // bundle when another caller (e.g. prewarm) is downloading the same content concurrently.
    public func saveContent(contentHash: String, files: [String: Data]) throws {
        let contentDir = baseDirectory.appendingPathComponent(contentHash)

        guard !fileManager.fileExists(atPath: contentDir.path) else { return }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let staging = baseDirectory.appendingPathComponent(".staging-\(UUID().uuidString)")

        do {
            try writeStagedContent(files: files, to: staging)
            try fileManager.moveItem(at: staging, to: contentDir)
        } catch {
            try? fileManager.removeItem(at: staging)

            // A concurrent writer may have produced the final content first, that's a success.
            if fileManager.fileExists(atPath: contentDir.path) {
                return
            }
            throw error
        }
    }

    public func getContentDirectory(contentHash: String) -> URL? {
        let contentDir = baseDirectory.appendingPathComponent(contentHash)
        guard fileManager.fileExists(atPath: contentDir.path) else { return nil }
        return contentDir
    }

    public func contentExists(contentHash: String) -> Bool {
        let contentDir = baseDirectory.appendingPathComponent(contentHash)
        return fileManager.fileExists(atPath: contentDir.path)
    }

    public func hasFileEntry(contentHash: String, relativePath: String) -> Bool {
        let contentDir = baseDirectory.appendingPathComponent(contentHash)
        let fileURL = contentDir.appendingPathComponent(relativePath)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    public func loadContent(contentHash: String, relativePath: String) -> Data? {
        let contentDir = baseDirectory.appendingPathComponent(contentHash)
        let fileURL = contentDir.appendingPathComponent(relativePath)
        return fileManager.contents(atPath: fileURL.path)
    }

    public func deleteContent(contentHash: String) throws {
        let contentDir = baseDirectory.appendingPathComponent(contentHash)
        guard fileManager.fileExists(atPath: contentDir.path) else { return }
        try fileManager.removeItem(at: contentDir)
    }

    public func deleteAll() throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.removeItem(at: baseDirectory)
    }

    public func chatEntrypointRelativePath() -> String {
        "worker/index.js"
    }
}

private extension DotNsContentStorage {
    func writeStagedContent(files: [String: Data], to staging: URL) throws {
        if
            files.count == 1,
            let entry = files.first, entry.key == "/" || entry.key.isEmpty {
            // Single root file: stage as a file
            try entry.value.write(to: staging)
            return
        }

        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        for (path, data) in files {
            var relativePath = path
            if relativePath.hasPrefix("/") {
                relativePath = String(relativePath.dropFirst())
            }
            guard !relativePath.isEmpty else { continue }

            let fileURL = staging.appendingPathComponent(relativePath)
            let parentDir = fileURL.deletingLastPathComponent()

            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            try data.write(to: fileURL)
        }
    }
}
