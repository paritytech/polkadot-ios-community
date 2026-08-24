import Foundation
import SubstrateSdkExt

public extension PGASPallet {
    enum Constants {
        case maxClaimsPerPeriodPerPerson
        case maxClaimsPerPeriodPerLitePerson
        case pgasClaimAmount
        case suffix
    }
}

extension PGASPallet.Constants: ConstantPathConvertible {
    public var name: String {
        switch self {
        case .maxClaimsPerPeriodPerPerson:
            "MaxClaimsPerPeriodPerPerson"
        case .maxClaimsPerPeriodPerLitePerson:
            "MaxClaimsPerPeriodPerLitePerson"
        case .pgasClaimAmount:
            "PgasClaimAmount"
        case .suffix:
            "Suffix"
        }
    }

    public var moduleName: String { PGASPallet.name }
}
