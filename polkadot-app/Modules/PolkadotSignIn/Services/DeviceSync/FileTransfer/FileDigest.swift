import CryptoKit
import Foundation

enum FileDigest {
    static func sha256(contentsOf url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: DeviceSyncFileProvider.chunkPayloadSize), !data.isEmpty {
            hasher.update(data: data)
        }
        return Data(hasher.finalize())
    }
}
