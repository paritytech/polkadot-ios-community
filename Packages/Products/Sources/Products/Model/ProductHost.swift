import Foundation

public struct ProductHost {
    static let dotDomain = "dot"
    static let liDomain = "li"
    static let shareRootDomains: Set<String> = [dotDomain, "paseo"]
    static let separator = "."

    public static let shareHosts: Set<String> = Set(shareRootDomains.map { $0 + separator + liDomain })

    let components: [String]

    public var name: String {
        let lastIndex = components.isShareDomain ? components.count - 3 : components.count - 2

        return components[0 ... lastIndex].joined(separator: ProductHost.separator)
    }

    public func toDotDomain() -> String {
        guard components.isShareDomain else {
            return components.joined(separator: ProductHost.separator)
        }

        let nameComponents = components[0 ..< components.count - 2] + [ProductHost.dotDomain]

        return nameComponents.joined(separator: ProductHost.separator)
    }

    public init?(rawString: String) {
        let parsedComponent = rawString.components(separatedBy: ProductHost.separator)

        guard !parsedComponent.contains(where: \.isEmpty) else {
            return nil
        }

        guard parsedComponent.isDotDomain || parsedComponent.isShareDomain else {
            return nil
        }

        components = parsedComponent
    }
}

public extension ProductHost {
    static func fromUrl(_ url: URL) -> ProductHost? {
        guard let rawHost = url.host() else {
            return nil
        }

        return ProductHost(rawString: rawHost)
    }

    static func fromNavigationDestination(_ dest: String) -> ProductHost? {
        guard let url = URL(string: dest), url.host() != nil else {
            return ProductHost(rawString: dest)
        }

        return ProductHost.fromUrl(url)
    }
}

private extension [String] {
    var isDotDomain: Bool {
        count >= 2 && self.last == ProductHost.dotDomain
    }

    var isShareDomain: Bool {
        count >= 3 && ProductHost.shareRootDomains.contains(self[count - 2]) && self[count - 1] == ProductHost.liDomain
    }
}
