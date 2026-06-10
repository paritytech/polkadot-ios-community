import Foundation
import SubstrateSdk
import UIKitExt

extension JSONRPCError: @retroactive ErrorContentConvertible {
    public func toErrorContent() -> ErrorContent {
        let title: String
        let details: String

        if let data {
            title = message
            details = "\(data) (code \(code))"
        } else {
            title = String(localized: .Common.errorRpc)
            details = "\(message) (code \(code))"
        }

        return ErrorContent(title: title, message: details)
    }
}
