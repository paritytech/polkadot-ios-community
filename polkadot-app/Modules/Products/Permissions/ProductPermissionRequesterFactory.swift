import Foundation
import Products

enum ProductPermissionRequesterFactory {
    static func create(router: ProductPermissionRouting) -> ProductPermissionRequesting {
        let requester = ProductPermissionRequester(router: router)

        #if FEATURE_PRODUCTS
            return requester
        #else
            return AutoAllowProductPermissionRequester(
                allowedLabels: [AppConfig.DotNs.dotNsGetSome],
                wrapped: requester
            )
        #endif
    }
}
