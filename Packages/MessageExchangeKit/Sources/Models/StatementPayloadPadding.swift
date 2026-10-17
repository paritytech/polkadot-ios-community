import Foundation

/// Pads a statement plaintext with trailing zeros to a power-of-two bucket (at least `minBucketSize`)
/// so a response and a short request are indistinguishable by length.
public struct StatementPayloadPadding: Equatable {
    public static let minBucketSize = 1_024

    // ChaCha20-Poly1305 nonce (12) + tag (16).
    static let encryptionOverhead = 28

    let maxPlaintextSize: Int

    /// - Parameter maxPayloadSize: the size limit of the statement's SCALE-encoded data field.
    public init(maxPayloadSize: Int) {
        let lengthPrefixSize = Self.compactLength(of: maxPayloadSize)
        maxPlaintextSize = max(0, maxPayloadSize - Self.encryptionOverhead - lengthPrefixSize)
    }

    public func pad(_ plaintext: Data) -> Data {
        guard plaintext.count < maxPlaintextSize else {
            return plaintext
        }

        let targetSize = min(bucketSize(for: plaintext.count), maxPlaintextSize)
        return plaintext + Data(count: targetSize - plaintext.count)
    }

    func bucketSize(for size: Int) -> Int {
        var bucket = Self.minBucketSize

        while bucket < size {
            bucket <<= 1
        }

        return bucket
    }
}

private extension StatementPayloadPadding {
    static func compactLength(of value: Int) -> Int {
        switch value {
        case ..<(1 << 6):
            1
        case ..<(1 << 14):
            2
        case ..<(1 << 30):
            4
        default:
            5
        }
    }
}
