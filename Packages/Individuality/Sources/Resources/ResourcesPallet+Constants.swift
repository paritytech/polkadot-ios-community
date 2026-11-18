import Foundation
import SubstrateSdkExt

public extension ResourcesPallet {
    enum Constants {
        case longTermStoragePeriodDuration
        case notificationPeriodDuration
    }
}

extension ResourcesPallet.Constants: ConstantPathConvertible {
    public var name: String {
        switch self {
        case .longTermStoragePeriodDuration:
            "LongTermStoragePeriodDuration"
        case .notificationPeriodDuration:
            "NotificationPeriodDuration"
        }
    }

    public var moduleName: String { ResourcesPallet.name }
}
