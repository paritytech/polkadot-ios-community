import Foundation
import Testing
import ChainRegistry
import Products
import EventCenter

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

        try await waitForSetupFailure(on: spy, timeout: 120)

        #expect(spy.didFailSetupCallCount == 1, "Expected one setup failure to be reported")
        #expect(spy.failureKinds == [.configuration(.tld)], "Expected the configuration failure at the tld stage")
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

        try await waitForSetupFailure(on: spy, timeout: 120)

        #expect(spy.failureKinds == [.connectivity], "Expected connectivity failure instead of TLD failure")
    }

    @Test("path recovery reports connectivity recovery")
    @MainActor
    func pathRecoveryReportsConnectivityRecovery() async throws {
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

        pathMonitor.send(true)

        try await waitUntil(timeout: 5) { spy.didRecoverConnectivityCallCount > 0 }

        #expect(spy.didRecoverConnectivityCallCount == 1, "Expected one connectivity recovery report")
        #expect(migrator.migrateCallCount == 1, "Expected migrations to stay on the launch pass")
    }

    @Test("a path drop during setup reports connectivity immediately")
    @MainActor
    func pathDropDuringSetupReportsConnectivityImmediately() async throws {
        let spy = RootSetupOutputSpy()
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [
            makeChain(id: AppConfig.Chains.usernameChain),
            makeChain(id: AppConfig.Chains.bulletInChain),
            makeChain(id: AppConfig.Chains.assethubChain)
        ]

        let pathMonitor = MockNetworkPathMonitor()
        let interactor = makeInteractor(
            chainRegistry: chainRegistry,
            pathMonitor: pathMonitor,
            tldProvider: StubDotNsTldProvider(tld: nil)
        )
        interactor.presenter = spy

        let startedAt = Date()
        interactor.setup()

        // Lets setup pass the chain wait and enter the TLD retry sequence, so the drop lands on
        // work already in flight rather than on a launch that has barely started.
        try await Task.sleep(for: .milliseconds(500))

        pathMonitor.send(false)

        try await waitForSetupFailure(on: spy)

        #expect(spy.failureKinds == [.connectivity], "Expected a path drop to report connectivity")
        #expect(
            Date().timeIntervalSince(startedAt) < 8,
            "Expected the drop to be reported without waiting out the TLD retry sequence"
        )
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

    @Test("chain sync completing without the required chains fails at the chains stage")
    @MainActor
    func chainSyncWithoutRequiredChainsFails() async throws {
        let spy = RootSetupOutputSpy()
        let eventCenter = MockEventCenter()
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [makeChain(id: AppConfig.Chains.usernameChain)]

        let interactor = makeInteractor(chainRegistry: chainRegistry, eventCenter: eventCenter)
        interactor.presenter = spy

        let startedAt = Date()
        interactor.setup()

        eventCenter.notify(
            with: ChainSyncDidComplete(newOrUpdatedChains: [], removedChains: [])
        )

        try await waitForSetupFailure(on: spy)

        #expect(
            spy.failureKinds == [.configuration(.chains)],
            "Expected a configuration failure at the chains stage"
        )
        #expect(
            Date().timeIntervalSince(startedAt) < 8,
            "Expected the chains failure to be reported without waiting out the deadline"
        )
    }

    @Test("chain sync completing with the required chains reports no failure")
    @MainActor
    func chainSyncWithRequiredChainsSucceeds() async throws {
        let spy = RootSetupOutputSpy()
        let eventCenter = MockEventCenter()
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [
            makeChain(id: AppConfig.Chains.usernameChain),
            makeChain(id: AppConfig.Chains.bulletInChain),
            makeChain(id: AppConfig.Chains.assethubChain)
        ]

        let interactor = makeInteractor(chainRegistry: chainRegistry, eventCenter: eventCenter)
        interactor.presenter = spy

        interactor.setup()

        eventCenter.notify(
            with: ChainSyncDidComplete(newOrUpdatedChains: [], removedChains: [])
        )

        // Gives the event a window to land; an unexpected failure ends the wait early.
        try await waitUntil(timeout: 2) { spy.didFailSetupCallCount > 0 }

        #expect(
            spy.didFailSetupCallCount == 0,
            "Expected no failure on an empty delta when every required chain is present"
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
        eventCenter: EventCenterProtocol = MockEventCenter(),
        tldProvider: DotNsTldProviding = StubDotNsTldProvider(tld: "dot")
    ) -> RootInteractor {
        RootInteractor(
            chainRegistryClosure: { chainRegistry },
            migrator: migrator,
            logger: StubLogger(),
            resolver: MockDecisionResolver(),
            tokenManager: MockJWTTokenManager(),
            eventCenter: eventCenter,
            remoteConfigManager: remoteConfigManager,
            chainRegistryConfigurator: MockChainRegistryConfigurator(),
            productPrewarmer: MockProductContentPrewarmer(),
            pathMonitor: pathMonitor,
            tldProvider: tldProvider
        )
    }

    /// The retried TLD resolve and the ten second setup wait both land off the main actor and
    /// arrive seconds late on CI, so the timeout sits above both rather than fixing a settling time.
    /// TLD-failure tests pass 120 seconds to accommodate the 30-second initial timeout plus retries
    /// (worst case ~93 seconds total) plus CI latency and clock variation.
    @MainActor
    func waitForSetupFailure(on spy: RootSetupOutputSpy, timeout: TimeInterval = 15) async throws {
        try await waitUntil(timeout: timeout) { spy.didFailSetupCallCount > 0 }
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
