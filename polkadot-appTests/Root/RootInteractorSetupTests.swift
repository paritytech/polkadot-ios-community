import Foundation
import Testing
import ChainRegistry

@testable import polkadot_app

@Suite("Root interactor setup and retry")
struct RootInteractorSetupTests {
    @Test("migrations run exactly once across setup and retry")
    @MainActor
    func migrationsRunOnceAcrossSetupAndRetry() {
        let migrator = MockMigrator()
        let interactor = makeInteractor(migrator: migrator)

        interactor.setup()
        #expect(migrator.migrateCallCount == 1)

        interactor.retrySetup()
        #expect(migrator.migrateCallCount == 1)
    }
}

private extension RootInteractorSetupTests {
    @MainActor
    func makeInteractor(migrator: Migrating) -> RootInteractor {
        let chainRegistry = MockChainRegistry()

        return RootInteractor(
            chainRegistryClosure: { chainRegistry },
            migrator: migrator,
            logger: StubLogger(),
            resolver: MockDecisionResolver(),
            tokenManager: MockJWTTokenManager(),
            remoteConfigManager: MockRemoteConfigManager(),
            chainRegistryConfigurator: MockChainRegistryConfigurator(),
            browsePrewarmer: MockProductContentPrewarmer(),
            tldProvider: StubDotNsTldProvider(tld: "dot")
        )
    }
}
