import Foundation
import Operation_iOS

struct ChainAsset: Equatable, Hashable {
    let chain: ChainModel
    let asset: AssetModel
}

extension ChainAsset {
    var isUtilityAsset: Bool {
        chain.utilityAsset()?.assetId == asset.assetId
    }
}
