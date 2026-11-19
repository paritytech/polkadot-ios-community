import CryptoKit
import Foundation

extension Data {
    var sha256Digest: Data {
        Data(SHA256.hash(data: self))
    }
}
