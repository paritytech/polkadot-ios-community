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
        #expect(spy.failureKinds == [.unknown], "Expected the unknown failure kind")
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
        #expect(spy.failureKinds == [.unknown], "Expected the unknown failure kind")
        #expect(spy.didDecideCallCount == 0, "Expected no destination reported")
        #expect(chainRegistry.chainsUnsubscribeCallCount == 1, "Expected chain wait to be cancelled")
    }

    @Test("unsatisfied path outranks a TLD failure")
    @MainActor
    func unsatisfiedPathOutranksTldFailure() async throws {
        let spy = RootSetupOutputSpy()
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [
            makeChain(id: AppConfig.Chains.usernameChain),
            makeChain(id: AppConfig.Chains.bulletInChain),
            makeChain(id: AppConfig.Chains.assethubChain)
        ]

        let pathMonitor = MockNetworkPathMonitor(initial: false)
        let interactor = makeInteractor(
            chainRegistry: chainRegistry,
            pathMonitor: pathMonitor,
            tldProvider: StubDotNsTldProvider(tld: nil)
        )
        interactor.presenter = spy

        interactor.setup()

        try await waitForSetupFailure(on: spy)

        #expect(spy.failureKinds == [.connectivity], "Expected connectivity failure instead of TLD failure")
    }

    @Test("path recovery retries setup without re-running migrations")
    @MainActor
    func pathRecoveryRetriesSetupWithoutMigrations() async throws {
        let spy = RootSetupOutputSpy()
        let migrator = MockMigrator()
        let chainRegistry = MockChainRegistry()
        let pathMonitor = MockNetworkPathMonitor(initial: false)

        let interactor = makeInteractor(
            migrator: migrator,
            chainRegistry: chainRegistry,
            pathMonitor: pathMonitor
        )
        interactor.presenter = spy

        interactor.setup()

        try await waitForSetupFailure(on: spy)
        #expect(spy.failureKinds == [.connectivity])
        #expect(chainRegistry.chainsSubscribeCallCount == 1)

        pathMonitor.send(true)

        try await waitUntil(timeout: 5) { chainRegistry.chainsSubscribeCallCount == 2 }

        #expect(chainRegistry.chainsSubscribeCallCount == 2, "Expected path recovery to re-run setup")
        #expect(migrator.migrateCallCount == 1, "Expected migrations to stay on the launch pass")
    }

    @Test("cold offline launch fails fast")
    @MainActor
    func coldOfflineLaunchFailsFast() async throws {
        let spy = RootSetupOutputSpy()
        let chainRegistry = MockChainRegistry()
        let pathMonitor = MockNetworkPathMonitor(initial: false)

        let interactor = makeInteractor(
            chainRegistry: chainRegistry,
            pathMonitor: pathMonitor
        )
        interactor.presenter = spy

        let startedAt = Date()
        interactor.setup()

        try await waitForSetupFailure(on: spy)

        #expect(spy.failureKinds == [.connectivity], "Expected connectivity failure when offline")
        #expect(
            Date().timeIntervalSince(startedAt) < 8,
            "Expected the offline deadline, not the full ten seconds"
        )
    }

    @Test("warm offline launch still succeeds")
    @MainActor
    func warmOfflineLaunchStillSucceeds() async throws {
        let spy = RootSetupOutputSpy()
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [
            makeChain(id: AppConfig.Chains.usernameChain),
            makeChain(id: AppConfig.Chains.bulletInChain),
            makeChain(id: AppConfig.Chains.assethubChain)
        ]
        let pathMonitor = MockNetworkPathMonitor(initial: false)

        let interactor = makeInteractor(
            chainRegistry: chainRegistry,
            pathMonitor: pathMonitor
        )
        interactor.presenter = spy

        interactor.setup()

        try await waitUntil(timeout: 8) { spy.didDecideCallCount > 0 }

        #expect(
            spy.didDecideCallCount == 1,
            "Expected a warm offline launch to reach a destination"
        )
        #expect(
            spy.didFailSetupCallCount == 0,
            "Expected no setup failure offline when everything is cached"
        )
    }

    @Test("invalid remote config fails at the config stage")
    @MainActor
    func invalidRemoteConfigFailsAtConfigStage() async throws {
        let spy = RootSetupOutputSpy()
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [
            makeChain(id: AppConfig.Chains.usernameChain),
            makeChain(id: AppConfig.Chains.bulletInChain),
            makeChain(id: AppConfig.Chains.assethubChain)
        ]
        let remoteConfigManager = MockRemoteConfigManager()
        remoteConfigManager.errorToThrow = RemoteConfigError.invalidConfig

        let interactor = makeInteractor(
            chainRegistry: chainRegistry,
            remoteConfigManager: remoteConfigManager
        )
        interactor.presenter = spy

        interactor.setup()

        try await waitForSetupFailure(on: spy)

        #expect(
            spy.failureKinds == [.configuration(.config)],
            "Expected a configuration failure at the config stage"
        )
    }
}

private extension RootInteractorSetupTests {
    @MainActor
    func makeInteractor(
        migrator: Migrating = MockMigrator(),
        chainRegistry: MockChainRegistry = MockChainRegistry(),
        pathMonitor: NetworkPathMonitoring = MockNetworkPathMonitor(),
        remoteConfigManager: MockRemoteConfigManager = MockRemoteConfigManager(),
        tldProvider: DotNsTldProviding = StubDotNsTldProvider(tld: "dot")
    ) -> RootInteractor {
        RootInteractor(
            chainRegistryClosure: { chainRegistry },
            migrator: migrator,
            logger: StubLogger(),
            resolver: MockDecisionResolver(),
            tokenManager: MockJWTTokenManager(),
            remoteConfigManager: remoteConfigManager,
            chainRegistryConfigurator: MockChainRegistryConfigurator(),
            productPrewarmer: MockProductContentPrewarmer(),
            pathMonitor: pathMonitor,
            tldProvider: tldProvider
        )
    }

    /// The retried TLD resolve and the ten second setup wait both land off the main actor and
    /// arrive seconds late on CI, so the timeout sits above both rather than fixing a settling time.
    @MainActor
    func waitForSetupFailure(on spy: RootSetupOutputSpy) async throws {
        try await waitUntil(timeout: 15) { spy.didFailSetupCallCount > 0 }
    }

    @MainActor
    func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
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
