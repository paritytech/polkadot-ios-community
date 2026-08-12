import Foundation

protocol DeeplinkSchemeNormalizing {
    func normalize(_ url: URL) -> URL
}

/// Rewrites known app deeplink schemes to the active build scheme so links generated
/// for one build flavor open in the other (e.g. a prod desktop pairing QR on a dev build).
struct DeeplinkSchemeNormalizer: DeeplinkSchemeNormalizing {
    private let activeScheme: String
    private let possibleInputSchemes: Set<String>

    init(
        activeScheme: String = AppConfig.DeepLink.scheme,
        possibleInputSchemes: Set<String> = AppConfig.DeepLink.knownSchemes
    ) {
        self.activeScheme = activeScheme
        self.possibleInputSchemes = possibleInputSchemes
    }

    func normalize(_ url: URL) -> URL {
        guard
            let scheme = url.scheme?.lowercased(),
            possibleInputSchemes.contains(scheme),
            scheme != activeScheme,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        components.scheme = activeScheme
        return components.url ?? url
    }
}
