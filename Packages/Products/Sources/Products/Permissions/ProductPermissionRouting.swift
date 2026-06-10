import Foundation

@MainActor
public protocol ProductPermissionRouting: AnyObject {
    func showPrompt(context: ProductPermissionContext)
}
