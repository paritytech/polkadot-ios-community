import Foundation
import SubstrateSdkExt

extension CoinagePallet {
    enum ViewFunction {
        case getFreeUnloadTokens
    }
}

extension CoinagePallet.ViewFunction: ViewFunctionCallConvertible {
    var name: String {
        switch self {
        case .getFreeUnloadTokens:
            "get_free_unload_token_info"
        }
    }

    var moduleName: String { CoinagePallet.name }
}
