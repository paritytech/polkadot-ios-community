import Foundation
import SubstrateSdk
import Operation_iOS

extension ChainModel: ChainProtocol {
    var disabledCheckMetadataHash: Bool {
        true
    }

    var base58Prefix: UInt16 {
        switch chainFormat {
        case let .substrate(addressPrefix):
            addressPrefix
        case .ethereum:
            42
        }
    }

    func assetInteface(for assetId: AssetId) -> (any SubstrateSdk.AssetProtocol)? {
        asset(for: assetId)
    }

    func chainAssetInterface(for assetId: SubstrateSdk.AssetId) -> ChainAssetProtocol? {
        chainAsset(for: assetId)
    }

    func chainAssetsInterface() -> [any SubstrateSdk.ChainAssetProtocol] {
        chainAssets()
    }

    func address(for accountId: AccountId) throws -> AccountAddress {
        try accountId.toAddress(using: chainFormat)
    }
}

extension AssetModel: AssetProtocol {}

extension ChainAssetId {
    var stringValue: String { "\(chainId)-\(assetId)" }
}

extension ChainAsset: ChainAssetProtocol {
    var chainInterface: ChainProtocol {
        chain
    }

    var assetInterface: AssetProtocol {
        asset
    }

    public var chainAssetId: ChainAssetId {
        ChainAssetId(chainId: chain.chainId, assetId: asset.assetId)
    }
}

enum ChainAssetConversionError: Error {
    case unsupportedAsset(String)
}

extension ChainAsset: Identifiable {
    var identifier: String { chainAssetId.stringValue }
}
