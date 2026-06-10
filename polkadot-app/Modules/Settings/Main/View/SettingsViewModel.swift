import UIKit
import PolkadotUI

enum SettingsViewModel {
    struct AttentionDetails {
        let message: String
        let imageResource: ImageResource
    }

    enum CellType: Hashable {
        case backup
        case theme
        case currency
        case revoke
        case linkedDevices
        case apps
        case blockedUsers
        case termsOfUse
        case privacy
        case contactUs

        var title: String {
            switch self {
            case .backup: String(localized: .settingsCellBackup)
            case .theme: String(localized: .settingsCellTheme)
            case .currency: String(localized: .settingsCellCurrency)
            case .revoke: String(localized: .settingsCellRecover)
            case .linkedDevices: String(localized: .settingsCellLinkedDevices)
            case .apps: String(localized: .settingsCellApps)
            case .blockedUsers: String(localized: .settingsCellBlockedUsers)
            case .termsOfUse: String(localized: .settingsCellTerms)
            case .privacy: String(localized: .settingsCellPrivacy)
            case .contactUs: String(localized: .settingsCellContactUs)
            }
        }

        var attentionDetails: AttentionDetails? {
            switch self {
            case .backup:
                AttentionDetails(
                    message: String(localized: .settingsCellBackupAttention),
                    imageResource: .error
                )
            default:
                nil
            }
        }
    }

    enum Section: String, CaseIterable {
        case general
        case security
        case legal
        case payments
        case support

        var header: String {
            switch self {
            case .general: String(localized: .settingsSectionGeneral)
            case .payments: String(localized: .settingsSectionPayments)
            case .security: String(localized: .settingsSectionSecurity)
            case .legal: String(localized: .settingsSectionLegal)
            case .support: String(localized: .settingsSectionSupport)
            }
        }

        var cells: [CellType] {
            switch self {
            case .general: [.theme]
            case .payments: [.revoke]
            case .security: [.backup, .apps, .linkedDevices, .blockedUsers]
            case .legal: [.privacy, .termsOfUse]
            case .support: [.contactUs]
            }
        }
    }

    struct Content {
        let sections: [SettingsViewLayout.Section]
        let appVersion: String?

        static let empty = Content(sections: [], appVersion: nil)
    }
}
