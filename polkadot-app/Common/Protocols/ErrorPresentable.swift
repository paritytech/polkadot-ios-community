import Foundation
import SubstrateSdk
import UIKitExt

protocol ErrorPresentable: AnyObject {
    func present(error: ErrorContent, from view: ControllerBackedProtocol?) -> Bool
}

extension ErrorPresentable {
    @discardableResult
    func present(error: Error, from view: ControllerBackedProtocol?) -> Bool {
        guard let content = errorContent(from: error) else {
            return false
        }
        return present(error: content, from: view)
    }

    func errorContent(from error: Error) -> ErrorContent? {
        if let contentConvertibleError = error as? ErrorContentConvertible {
            return contentConvertibleError.toErrorContent()
        }

        if (error as NSError).domain == NSURLErrorDomain {
            let title = String(localized: .Common.errorUrlDomain)
            let message = String(localized: .Common.errorMessage)

            return ErrorContent(title: title, message: message)
        }

        return nil
    }
}
