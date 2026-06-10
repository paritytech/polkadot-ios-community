import Foundation
import FoundationExt

public enum IpfsFetcherError: Error {
    case invalidHash
}

public protocol IpfsFetching {
    func lookupBy(rawHash: Data) async throws -> Data
}

public final class IpfsFetcher: IpfsFetching {
    private let converter: HexToCIDConverting
    private let session: URLSession

    public init(ipfsBaseURL: URL, session: URLSession = URLSession.shared) {
        converter = HexToCIDConverter(ipfsBaseURL: ipfsBaseURL)
        self.session = session
    }

    public func lookupBy(rawHash: Data) async throws -> Data {
        guard let url = converter.convertToIPFSURL(hash: rawHash, codec: .raw) else {
            throw IpfsFetcherError.invalidHash
        }

        let (data, response) = try await session.data(from: url)
        try response.ensureSuccess()

        return data
    }
}
