import Foundation
import SubstrateSdk
import SubstrateSdkExt
import Individuality
import BigInt

extension CoinagePallet {
    enum Constants {
        case assetUnit
        case maxConsolidation
        case maximumExponent
        case minimumExponent
        case unloadTokenTimePeriod
        case unloadTokenPerPeriodForPeople
        case unloadTokenPerPeriodForLitePeople
        case maxBatchUnpaidLoad
        case maxFreeUnloadTokensPerTimePeriod
    }
}

extension CoinagePallet.Constants: ConstantPathConvertible {
    var name: String {
        switch self {
        case .assetUnit:
            "UnderlyingAssetUnit"
        case .maxConsolidation:
            "MaxConsolidation"
        case .maximumExponent:
            "MaximumExponent"
        case .minimumExponent:
            "MinimumExponent"
        case .maxFreeUnloadTokensPerTimePeriod:
            "MaxFreeUnloadTokensPerTimePeriod"
        case .unloadTokenTimePeriod:
            "UnloadTokenTimePeriodPeopleLitePeople"
        case .unloadTokenPerPeriodForPeople:
            "UnloadTokenPerTimePeriodForPeople"
        case .unloadTokenPerPeriodForLitePeople:
            "UnloadTokenPerTimePeriodForLitePeople"
        case .maxBatchUnpaidLoad:
            "MaxBatchUnpaidLoad"
        }
    }

    var moduleName: String { CoinagePallet.name }
}
