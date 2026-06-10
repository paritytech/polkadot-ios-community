import Foundation
import SubstrateSdk
import SubstrateSdkExt
import Individuality

extension CoinagePallet {
    enum Storage {
        case consumedFreeUnloadTokens
        case recyclersCoinToRecycler
        case coinsByOwner
        case recyclersUnloaded
    }
}

extension CoinagePallet.Storage: StoragePathConvertible {
    var name: String {
        switch self {
        case .recyclersCoinToRecycler:
            "RecyclersCoinToRecycler"
        case .consumedFreeUnloadTokens:
            "ConsumedFreeUnloadTokens"
        case .coinsByOwner:
            "CoinsByOwner"
        case .recyclersUnloaded:
            "RecyclersUnloaded"
        }
    }

    var moduleName: String { CoinagePallet.name }
}
