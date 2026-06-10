import CID
import CarParser
import Foundation
import FoundationExt

public enum CarFetcherError: Error {
    case invalidContentHash
}

public protocol CarFetcherProtocol {
    func fetchCar(contentHash: Data) async throws -> Data
}

public final class CarFetcher: CarFetcherProtocol {
    private let gatewayBaseUrl: URL
    private let session: URLSession

    public init(gatewayBaseUrl: URL, session: URLSession = .shared) {
        self.gatewayBaseUrl = gatewayBaseUrl
        self.session = session
    }

    public func fetchCar(contentHash: Data) async throws -> Data {
        guard let cid = try? CID(contentHash) else {
            throw CarFetcherError.invalidContentHash
        }

        let cidString = cid.toBaseEncodedString

        // Phase 1: try raw fetch — handles legacy deployments where CID points to a CAR file
        let rawUrl = URL(string: cidString, relativeTo: gatewayBaseUrl)!
        let rawData = try await fetchData(from: rawUrl)

        if CarParser.looksLikeCarArchive(rawData) {
            return rawData
        }

        // Phase 2: re-fetch with format=car for directory CIDs
        let formatQuery = [URLQueryItem(name: "format", value: "car")]
        let formatUrl = rawUrl.appending(queryItems: formatQuery)

        var request = URLRequest(url: formatUrl)
        request.setValue("application/vnd.ipld.car", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        try response.ensureSuccess()

        return data
    }

    // MARK: - Private

    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try response.ensureSuccess()

        return data
    }
}
