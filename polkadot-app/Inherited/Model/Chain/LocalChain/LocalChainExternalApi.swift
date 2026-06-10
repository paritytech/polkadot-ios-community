import Foundation
import SubstrateSdk

enum LocalChainApiExternalType: String {
    case transactionHistory
    case hop
}

struct LocalChainExternalApi: Equatable, Codable, Hashable {
    let apiType: String
    let serviceType: String
    let url: URL
    let parameters: JSON?

    var identifier: String {
        Self.createId(from: apiType, serviceType: serviceType, url: url)
    }

    static func createId(from apiType: String, serviceType: String, url: URL) -> String {
        apiType + "-" + serviceType + url.absoluteString
    }
}

struct LocalChainExternalApiSet: Codable, Equatable, Hashable {
    let apis: Set<LocalChainExternalApi>

    func getApis(for type: LocalChainApiExternalType) -> Set<LocalChainExternalApi>? {
        let targetApis = apis.filter { LocalChainApiExternalType(rawValue: $0.apiType) == type }
        return !targetApis.isEmpty ? Set(targetApis) : nil
    }

    func history() -> Set<LocalChainExternalApi>? {
        getApis(for: .transactionHistory)
    }

    func hop() -> Set<LocalChainExternalApi>? {
        getApis(for: .hop)
    }

    init(localApis: Set<LocalChainExternalApi>) {
        apis = localApis
    }

    init(remoteApi: RemoteChainExternalApiSet) {
        apis = Set<LocalChainExternalApi>()
            .addingApis(from: remoteApi.transactionHistory, apiType: .transactionHistory)
            .addingNodeUrls(from: remoteApi.hop, apiType: .hop)
    }
}

extension Set<LocalChainExternalApi> {
    func addingApis(from remoteApis: [RemoteChainExternalApi]?, apiType: LocalChainApiExternalType) -> Set<Element> {
        guard let remoteApis else {
            return self
        }

        let localApis = remoteApis.map {
            LocalChainExternalApi(
                apiType: apiType.rawValue,
                serviceType: $0.type,
                url: $0.url,
                parameters: $0.parameters
            )
        }

        return union(Set(localApis))
    }

    func addingNodeUrls(from urls: [URL]?, apiType: LocalChainApiExternalType) -> Set<Element> {
        guard let urls else {
            return self
        }

        let localApis = urls.map {
            LocalChainExternalApi(
                apiType: apiType.rawValue,
                serviceType: apiType.rawValue,
                url: $0,
                parameters: nil
            )
        }

        return union(Set(localApis))
    }
}
