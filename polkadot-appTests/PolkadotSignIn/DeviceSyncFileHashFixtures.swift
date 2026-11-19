import CryptoKit
import Foundation

extension Data {
    static let unverifiedFileHash = Data(repeating: 0, count: 32)

    var sha256Digest: Data {
        Data(SHA256.hash(data: self))
    }
}
