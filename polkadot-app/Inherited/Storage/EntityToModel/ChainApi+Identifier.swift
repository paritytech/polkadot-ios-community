import Foundation

extension CDChainApi {
    var identifier: String {
        LocalChainExternalApi.createId(
            from: apiType!,
            serviceType: serviceType!,
            url: url!
        )
    }
}
