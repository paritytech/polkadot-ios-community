import Foundation
import Testing
import ChainRegistry
import Products

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

    @Test("TLD resolution failure gates destination")
    @MainActor
    func tldFailureGatesDestination() async throws {
        let spy = RootSetupOutputSpy()
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [
            makeChain(id: AppConfig.Chains.usernameChain),
            makeChain(id: AppConfig.Chains.bulletInChain),
            makeChain(id: AppConfig.Chains.assethubChain)
        ]

        let interactor = makeInteractor(
            chainRegistry: chainRegistry,
            tldProvider: StubDotNsTldProvider(tld: nil)
        )
        interactor.presenter = spy

        interactor.setup()

        try await waitForSetupFailure(on: spy)

        #expect(spy.didFailSetupCallCount == 1, "Expected one setup failure to be reported")
        #expect(spy.didDecideCallCount == 0, "Expected no destination decision (gate holds)")
    }

    @Test("setup deadline expiry reports failure and no destination")
    @MainActor
    func setupDeadlineExpiryReportsFailureAndNoDestination() async throws {
        let spy = RootSetupOutputSpy()
        let chainRegistry = MockChainRegistry()
        // No chains emitted; the subscription never resolves

        let interactor = makeInteractor(chainRegistry: chainRegistry)
        interactor.presenter = spy

        interactor.setup()

        try await waitForSetupFailure(on: spy)

        #expect(spy.didFailSetupCallCount == 1, "Expected failure reported after deadline")
        #expect(spy.didDecideCallCount == 0, "Expected no destination reported")
        #expect(chainRegistry.chainsUnsubscribeCallCount == 1, "Expected chain wait to be cancelled")
    }
}

private extension RootInteractorSetupTests {
    @MainActor
    func makeInteractor(
        migrator: Migrating = MockMigrator(),
        chainRegistry: MockChainRegistry = MockChainRegistry(),
        tldProvider: DotNsTldProviding = StubDotNsTldProvider(tld: "dot")
    ) -> RootInteractor {
        RootInteractor(
            chainRegistryClosure: { chainRegistry },
            migrator: migrator,
            logger: StubLogger(),
            resolver: MockDecisionResolver(),
            tokenManager: MockJWTTokenManager(),
            remoteConfigManager: MockRemoteConfigManager(),
            chainRegistryConfigurator: MockChainRegistryConfigurator(),
            browsePrewarmer: MockProductContentPrewarmer(),
            tldProvider: tldProvider
        )
    }

    /// Polls until the spy reports a setup failure, or the deadline passes.
    /// The retried TLD resolve and the ten second setup wait both land off the main actor and
    /// arrive seconds late on CI, so the deadline sits above both rather than fixing a settling time.
    @MainActor
    func waitForSetupFailure(on spy: RootSetupOutputSpy) async throws {
        let deadline = Date().addingTimeInterval(15)
        while spy.didFailSetupCallCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func makeChain(id: String) -> ChainModel {
        ChainModel(
            chainId: id,
            parentId: nil,
            name: id,
            assets: [],
            nodes: [],
            nodeSwitchStrategy: .roundRobin,
            addressPrefix: 0,
            explicitGenesisHash: nil,
            types: nil,
            icon: nil,
            options: nil,
            externalApis: nil,
            explorers: nil,
            order: 0,
            additional: nil,
            syncMode: .full
        )
    }
}
