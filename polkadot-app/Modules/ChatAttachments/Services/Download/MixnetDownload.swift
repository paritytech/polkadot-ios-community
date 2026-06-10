import Foundation
import Operation_iOS

struct MixnetDownload: Hashable {
    let metadataHashHex: String
    let lastChunkIndex: Int32
    let totalChunks: Int32
    let metadata: Data?
    let downloadedBytes: Int64
}

extension MixnetDownload: Operation_iOS.Identifiable {
    var identifier: String { metadataHashHex }
}

struct MixnetDownloadChunkIndex: Hashable {
    let metadataHashHex: String
    let lastChunkIndex: Int32
    let downloadedBytes: Int64
}

extension MixnetDownloadChunkIndex: Operation_iOS.Identifiable {
    var identifier: String { metadataHashHex }
}
