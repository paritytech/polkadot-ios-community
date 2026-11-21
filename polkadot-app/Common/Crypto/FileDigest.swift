import CryptoKit
import Foundation

enum FileDigest {
    static let readSize = 1 << 20

    static func sha256(contentsOf url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: readSize), !data.isEmpty {
            hasher.update(data: data)
        }
        return Data(hasher.finalize())
    }
}
