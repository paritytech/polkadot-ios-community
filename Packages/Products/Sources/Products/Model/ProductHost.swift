import Foundation

public struct ProductHost {
    static let dotDomain = "dot"
    static let liDomain = "li"
    static let separator = "."

    let components: [String]

    public var name: String {
        let lastIndex = components.isDotLiDomain ? components.count - 3 : components.count - 2

        return components[0 ... lastIndex].joined(separator: ProductHost.separator)
    }

    public func toDotDomain() -> String {
        let lastIndex = components.isDotLiDomain ? components.count - 2 : components.count - 1

        return components[0 ... lastIndex].joined(separator: ProductHost.separator)
    }

    public init?(rawString: String) {
        let parsedComponent = rawString.components(separatedBy: ProductHost.separator)

        guard !parsedComponent.contains(where: \.isEmpty) else {
            return nil
        }

        guard parsedComponent.isDotDomain || parsedComponent.isDotLiDomain else {
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
        if let url = URL(string: dest) {
            ProductHost.fromUrl(url) ?? ProductHost(rawString: dest)
        } else {
            ProductHost(rawString: dest)
        }
    }
}

private extension [String] {
    var isDotDomain: Bool {
        count >= 2 && self.last == ProductHost.dotDomain
    }

    var isDotLiDomain: Bool {
        count >= 3 && self[count - 2] == ProductHost.dotDomain && self[count - 1] == ProductHost.liDomain
    }
}
