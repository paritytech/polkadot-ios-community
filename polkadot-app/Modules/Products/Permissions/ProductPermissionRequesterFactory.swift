import Foundation
import Products

enum ProductPermissionRequesterFactory {
    static func create(router: ProductPermissionRouting) -> ProductPermissionRequesting {
        let requester = ProductPermissionRequester(router: router)
        // Ordered narrowest first. The trusted wrapper grants remote access only
        // and is not tied to the settings-screen build flag, so it still applies
        // in builds where `ProductAutoAllowList` is empty.
        let trusted = TrustedRemoteProductPermissionRequester(
            isTrustedForRemoteAccess: { ProductRemoteTrust.isTrustedForRemoteAccess(productId: $0) },
            wrapped: requester
        )
        return AutoAllowProductPermissionRequester(
            allowedLabels: ProductAutoAllowList.labels,
            wrapped: trusted
        )
    }
}
