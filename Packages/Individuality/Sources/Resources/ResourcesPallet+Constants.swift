import Foundation
import SubstrateSdkExt

public extension ResourcesPallet {
    enum Constants {
        case stmtStoreSlotsPerPeriod
        case liteStmtStoreSlotsPerPeriod
        case longTermStorageClaimsPerPeriod
        case longTermStoragePeriodDuration
        case stmtStoreReplacementCooldown
        case suffix
    }
}

extension ResourcesPallet.Constants: ConstantPathConvertible {
    public var name: String {
        switch self {
        case .stmtStoreSlotsPerPeriod:
            "StmtStoreSlotsPerPeriod"
        case .liteStmtStoreSlotsPerPeriod:
            "LiteStmtStoreSlotsPerPeriod"
        case .longTermStorageClaimsPerPeriod:
            "LongTermStorageClaimsPerPeriod"
        case .longTermStoragePeriodDuration:
            "LongTermStoragePeriodDuration"
        case .stmtStoreReplacementCooldown:
            "StmtStoreReplacementCooldown"
        case .suffix:
            "Suffix"
        }
    }

    public var moduleName: String { ResourcesPallet.name }
}
