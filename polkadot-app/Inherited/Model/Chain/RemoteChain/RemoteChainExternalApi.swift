import Foundation
import SubstrateSdk

struct RemoteChainExternalApi: Equatable, Codable {
    let type: String
    let url: URL
    let parameters: JSON?
}

struct RemoteChainExternalApiSet: Equatable, Codable {
    enum CodingKeys: String, CodingKey {
        case transactionHistory
        case hop
    }

    let transactionHistory: [RemoteChainExternalApi]?
    let hop: [URL]?
}
