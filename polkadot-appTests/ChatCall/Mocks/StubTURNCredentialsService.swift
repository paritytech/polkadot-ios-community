@testable import polkadot_app
import Foundation

/// Returns fixed TURN credentials without touching the network.
struct StubTURNCredentialsService: TURNCredentialsProviding {
    let credentials: TURNCredentials

    init(
        credentials: TURNCredentials = .init(
            servers: ["stun:stun.example.org:3478", "turn:turn.example.org:3478"],
            username: "user",
            password: "password",
            ttl: 3_600
        )
    ) {
        self.credentials = credentials
    }

    func issueCredentials() async throws -> TURNCredentials {
        credentials
    }
}
