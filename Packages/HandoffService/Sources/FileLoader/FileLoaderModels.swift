import Foundation
import Foundation_iOS
import NovaCrypto
import SubstrateSdk

public typealias FileTicket = Data
public typealias FileHash = Data

private extension FileTicket {
    static let ticketSize = 32
    static let ticketSignerContext = Data("signer".utf8)
    static let ticketEncryptorContext = Data("encryption".utf8)
}

public extension FileTicket {
    static func generateFileTicket() throws -> FileTicket {
        try FileTicket.randomOrError(of: ticketSize)
    }

    func deriveSigningKeypair() throws -> SNKeypairProtocol {
        let seed = try Self.ticketSignerContext.blake2b32WithKey(self)
        return try SNKeyFactory().createKeypair(fromSeed: seed)
    }

    func deriveMultiSigner() throws -> MultiSigner {
        let pubKey = try deriveSigningKeypair().publicKey().rawData()
        return .sr25519(pubKey)
    }

    func deriveEncryptor() throws -> FileEncrypting {
        let rawEncryptionKey = try Self.ticketEncryptorContext.blake2b32WithKey(self)
        return AESFileEncryptor(rawKey: rawEncryptionKey)
    }
}

public enum FileUploadingEvent {
    public struct Progress: Equatable {
        public let uploaded: Int
        public let total: Int
        public let uploadedHashes: [Data]

        public init(uploaded: Int, total: Int, uploadedHashes: [Data]) {
            self.uploaded = uploaded
            self.total = total
            self.uploadedHashes = uploadedHashes
        }
    }

    public struct Finished: Equatable {
        public let metadataHash: Data

        public init(metadataHash: Data) {
            self.metadataHash = metadataHash
        }
    }

    case onProgress(Progress)
    case onFinished(Finished)
    case onError(Error)
}

struct UploadedFile: ScaleCodable {
    let totalSize: UInt64
    let chunks: [Data]

    init(totalSize: UInt64, chunks: [Data]) {
        self.totalSize = totalSize
        self.chunks = chunks
    }

    init(scaleDecoder: ScaleDecoding) throws {
        totalSize = try UInt64(scaleDecoder: scaleDecoder)
        chunks = try [Data](scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: ScaleEncoding) throws {
        try totalSize.encode(scaleEncoder: scaleEncoder)
        try chunks.encode(scaleEncoder: scaleEncoder)
    }
}

public enum FileDownloadingEvent {
    public struct Progress: Equatable {
        public let downloaded: Int
        public let total: Int

        public init(downloaded: Int, total: Int) {
            self.downloaded = downloaded
            self.total = total
        }
    }

    case onProgress(Progress)
    case onFinished(FileHash)
    case onError(Error)
}

public enum FileDownloadingError: Error {
    case noMetadata(FileHash)
    case noChunk(FileHash)
}
