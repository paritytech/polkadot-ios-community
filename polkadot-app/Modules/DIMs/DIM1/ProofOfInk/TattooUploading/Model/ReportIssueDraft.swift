import Foundation

extension EmailDraft {
    static var reportIssue: EmailDraft = .init(
        subject: String(localized: .Tattoo.reportIssueSubject),
        message: String(localized: .Tattoo.reportIssueMessagePrefix),
        recipients: [CIKeys.reportIssueEmail],
        attachment: nil
    )
}
