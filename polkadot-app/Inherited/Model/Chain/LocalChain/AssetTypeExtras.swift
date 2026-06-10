import Foundation
import SubstrateSdk

struct StatemineAssetExtras: Codable {
    let assetId: String
    let palletName: String?
}

struct OrmlTokenExtras: Codable {
    let currencyIdScale: String
    let currencyIdType: String
    let existentialDeposit: String
    let transfersEnabled: Bool?
}

typealias AssetTypeExtras = JSON
