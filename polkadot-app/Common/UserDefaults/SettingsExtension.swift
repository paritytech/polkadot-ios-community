import Foundation
import Keystore_iOS

enum SettingsKey: String {
    case username
    case usernameClaimed
    case isPerson
    case waitingRoomNotificationDate
    case gameStartNotificationDate
    case registrationStartNotificationDates
    case voucherInUseDismissed
    case playerTooltipShown
    case swipeTooltipShown
    case selectedCurrencyCode
    case fiatOnrampSessionIds
    case fiatOnrampTrackedTransactionIds
    case gameAlarmId
    case gameAlarmFireDate
    case gameAlarmTimingSeconds
    case coinageSyncNeeded
    // Balance restored notification
    case coinageBackupRestorePending
    case coinScanHorizon
    case voucherScanHorizon
    case deviceEncryptId
    case nextSyncUpdateId
    case web3SummitVerified
    case themeSelected
    case gameCalendarReminder
    case backendSessionId
}

extension SettingsManagerProtocol {
    func integerArray(for setting: SettingsKey) -> [Int]? {
        anyValue(for: setting.rawValue) as? [Int]
    }

    func removeValue(for setting: SettingsKey) {
        removeValue(for: setting.rawValue)
    }

    func integer(for setting: SettingsKey) -> Int? {
        integer(for: setting.rawValue)
    }

    func set(value: Int, for setting: SettingsKey) {
        set(value: value, for: setting.rawValue)
    }

    func set(intArray: [Int], for setting: SettingsKey) {
        set(anyValue: intArray, for: setting.rawValue)
    }

    func set(value: Bool, for setting: SettingsKey) {
        set(value: value, for: setting.rawValue)
    }

    func value(for setting: SettingsKey) -> Bool {
        bool(for: setting.rawValue) ?? false
    }

    func set(string value: String, for key: SettingsKey) {
        set(anyValue: value, for: key.rawValue)
    }

    func string(for key: SettingsKey) -> String? {
        anyValue(for: key.rawValue) as? String
    }
}
