import Foundation
import SubstrateSdkExt

public extension ResourcesPallet {
    enum Constants {
        case stmtStoreSlotsPerPeriod
        case liteStmtStoreSlotsPerPeriod
        case longTermStorageClaimsPerPeriod
        case longTermStoragePeriodDuration
        case stmtStoreReplacementCooldown
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
        }
    }

    public var moduleName: String { ResourcesPallet.name }
}
