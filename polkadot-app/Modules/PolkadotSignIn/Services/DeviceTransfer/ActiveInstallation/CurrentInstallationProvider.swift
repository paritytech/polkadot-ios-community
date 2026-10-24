import Foundation
import Coinage

protocol CurrentInstallationProviding: Sendable {
    /// 32 random bytes made with the local database; a restore or reinstall gets a new one.
    func currentInstallationId() async throws -> Data
}

/// Shares coinage's installation row, so the active record and coin indices name the same installation.
/// Never call it inside another `performWrite`: the row is created on the shared writer.
struct CoinageCurrentInstallationProvider: CurrentInstallationProviding {
    let repository: CoinageCurrentInstallationRepositoryProtocol

    func currentInstallationId() async throws -> Data {
        try await repository.getOrCreateCurrent { try CoinageInstallationId.random() }.value
    }
}
