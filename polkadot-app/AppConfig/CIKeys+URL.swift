import Foundation

extension String {
    /// Converts an externalised configuration string (see `CIKeys`)
    /// into a `URL`. A malformed value is a build-time misconfiguration of
    /// `Scripts/inject-keys.sh` / `polkadot-app/env-vars.sh`, so it fails loudly.
    var asConfigURL: URL {
        guard let url = URL(string: self, encodingInvalidCharacters: false) else {
            fatalError(
                "Invalid configuration URL: \"\(self)\". "
                    + "Check Scripts/inject-keys.sh and polkadot-app/env-vars.sh."
            )
        }
        return url
    }
}
