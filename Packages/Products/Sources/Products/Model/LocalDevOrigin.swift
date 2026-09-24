import Foundation

/// A product served from a development server on the developer's own network instead of from dotNS.
///
/// The simulator reaches that server as `localhost`, since it shares the Mac's network stack. A device
/// has no tunnel back to the Mac, so it reaches it by the machine's own private address — which is also
/// what lets more than one device load the same server.
///
/// Private ranges only: a public address is never a development server, and treating one as such would
/// hand the host API to whoever answers at it.
public enum LocalDevOrigin {
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1"]
    private static let httpPrefix = "http://"
    private static let httpsPrefix = "https://"
    private static let labelPrefix = "dev-"

    /// Canonical `http://<host>[:<port>]` origin of `rawURL`, or `nil` when `rawURL` does not name a
    /// local development server. A missing scheme reads as http; https is rejected, since a dev server
    /// is served in the clear.
    public static func parseOrigin(_ rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        guard !lowercased.hasPrefix(httpsPrefix) else { return nil }

        let withScheme = lowercased.hasPrefix(httpPrefix) ? trimmed : httpPrefix + trimmed

        guard
            let components = URLComponents(string: withScheme),
            let host = components.host?.lowercased(),
            loopbackHosts.contains(host) || isPrivateIPv4(host)
        else {
            return nil
        }

        let port = components.port.map { ":\($0)" } ?? ""

        return httpPrefix + host + port
    }

    /// Label for the `ProductHost` a dev product's `ProductPage` is built around. Structural only —
    /// the identity a dev product transacts under is its origin, not this label (see
    /// `SPAConfiguration.productId`). `ProductHost` rejects empty sub-labels, so the port separator
    /// becomes a hyphen.
    public static func productLabel(forOrigin origin: String) -> String {
        let authority = origin.hasPrefix(httpPrefix) ? String(origin.dropFirst(httpPrefix.count)) : origin

        return labelPrefix + authority.replacingOccurrences(of: ":", with: "-")
    }

    /// Origin a dev product is served from, or nil for an ordinary dotNS product. A dev product is
    /// identified by its origin's authority, so the id parses straight back — a dotNS name never does,
    /// since its host is not a local address.
    public static func origin(forProductId productId: String) -> String? {
        parseOrigin(productId)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }

        let octets = parts.compactMap { UInt16($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else { return false }

        switch octets[0] {
        case 10: return true
        case 172: return (16 ... 31).contains(octets[1])
        case 192: return octets[1] == 168
        default: return false
        }
    }
}
