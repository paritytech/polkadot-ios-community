import Foundation
import NovaCrypto

enum CoingeckoAPI {
    static let baseURL = CIKeys.coingeckoBaseURL.asConfigURL
    static let price = "simple/price"

    static func priceHistory(for tokenId: String) -> String {
        "coins/\(tokenId)/market_chart/range"
    }
}
