import Foundation
import os
import NovaCrypto
import Operation_iOS
import Foundation_iOS
import SubstrateSdk
import ChainRegistry
import SubstrateSdkExt
import Products
import StructuredConcurrency

final class RootInteractor {
    private enum SetupWaitOutcome {
        case ready
        case deadlineExpired
    }

    private enum Constants {
        static let setupDeadlineSeconds: TimeInterval = 10
        static let tldTimeoutSeconds: TimeInterval = 10
        static let tldRetryMaxAttempts = 4
        static let tldRetryInitialDelay: Duration = .seconds(1)
    }

    weak var presenter: RootInteractorOutputProtocol?

    let chainRegistryClosure: ChainRegistryLazyClosure

    let migrator: Migrating
    let logger: LoggerProtocol
    let resolver: any DecisionResolver<RootDestination>
    let tokenManager: JWTTokenManaging
    let tldProvider: DotNsTldProviding

    let remoteConfigManager: RemoteConfigManaging
    let chainRegistryConfigurator: ChainRegistryConfiguring
    let productPrewarmer: ProductContentPrewarming
    let pathMonitor: NetworkPathMonitoring

    private var completionTask: Task<Void, Never>?
    private var didReportEstablishedUser = false
    private let isPathSatisfied = OSAllocatedUnfairLock(initialState: true)
    private var pathTask: Task<Void, Never>?

    #if TESTNET_FEATURE
        var appFactoryResetCheckerFactory: AppFactoryResetCheckerFactoryProtocol?
        private var appFactoryResetChecker: AppFactoryResetChecker?
    #endif

    init(
        chainRegistryClosure: @escaping ChainRegistryLazyClosure,
        migrator: Migrating,
        logger: LoggerProtocol,
        resolver: any DecisionResolver<RootDestination>,
        tokenManager: JWTTokenManaging,
        remoteConfigManager: RemoteConfigManaging,
        chainRegistryConfigurator: ChainRegistryConfiguring,
        productPrewarmer: ProductContentPrewarming,
        pathMonitor: NetworkPathMonitoring,
        tldProvider: DotNsTldProviding = DotNsTldProviderFacade.shared
    ) {
        self.chainRegistryClosure = chainRegistryClosure

        self.migrator = migrator
        self.logger = logger
        self.resolver = resolver
        self.tokenManager = tokenManager
        self.remoteConfigManager = remoteConfigManager
        self.chainRegistryConfigurator = chainRegistryConfigurator
        self.productPrewarmer = productPrewarmer
        self.pathMonitor = pathMonitor
        self.tldProvider = tldProvider
    }

    deinit {
        completionTask?.cancel()
        pathTask?.cancel()
    }

    @MainActor
    private func performCommonSetup(with chainRegistry: ChainRegistryProtocol) {
        completionTask?.cancel()

        setupChainUpdate(for: chainRegistry)
        fetchRemoteConfig()
        startPathMonitoringIfNeeded()

        startSetupCompletionTask(for: chainRegistry)
    }

    private func setupChainUpdate(for registry: ChainRegistryProtocol) {
        chainRegistryConfigurator.set(chainRegistry: registry)
    }

    private func runMigrators() {
        do {
            try migrator.migrate()
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemoteConfig() {
        remoteConfigManager.fetchRemoteConfigValues()
    }

    private func setupJWTManager() {
        let authProvider = AppAttestProviderResolver.resolve()

        tokenManager.setup(authProvider: authProvider)
        tokenManager.prewarm()
    }

    @MainActor
    private func prewarmProducts(for destination: RootDestination) {
        switch destination {
        case .dashboard:
            productPrewarmer.prewarm()
        default:
            break
        }
    }

    private func startSetupCompletionTask(for chainRegistry: ChainRegistryProtocol) {
        completionTask = Task { [weak self] in
            await self?.performSetupCompletion(for: chainRegistry)
        }
    }

    private func performSetupCompletion(for chainRegistry: ChainRegistryProtocol) async {
        let outcome = await waitForSetupInputs(for: chainRegistry)

        guard !Task.isCancelled else { return }

        if outcome == .deadlineExpired {
            await reportSetupFailure(kind: classifyFailure(fallback: .unknown))
            return
        }

        setupJWTManager()

        do {
            try await resolveTldIfNeeded()
        } catch {
            guard !Task.isCancelled else { return }
            await reportSetupFailure(kind: classifyFailure(fallback: .unknown))
            return
        }

        guard !Task.isCancelled else { return }

        await completeSetup()
    }

    /// Caches the DotNs TLD once chains and remote config are ready. Resolving here covers
    /// every onboarding path (username claim, iCloud recovery), so downstream built-in
    /// account derivation can read the TLD synchronously. A TLD persisted by a previous
    /// run is enough, so startup is not blocked offline; currentTld() kicks a background
    /// refresh on its own.
    private func resolveTldIfNeeded() async throws {
        guard tldProvider.currentTld() == nil else { return }

        _ = try await withRetry(
            maxAttempts: Constants.tldRetryMaxAttempts,
            initialDelay: Constants.tldRetryInitialDelay
        ) { [tldProvider] in
            try await withTimeout(.seconds(Constants.tldTimeoutSeconds)) {
                try await tldProvider.resolveTld()
            }
        }
    }

    /// Waits for the paired chain registry and remote config, bounded by ``Constants.setupDeadlineSeconds``.
    /// A chain or remote config failure is not fatal on its own: only the deadline gates startup.
    private func waitForSetupInputs(for chainRegistry: ChainRegistryProtocol) async -> SetupWaitOutcome {
        do {
            try await withTimeout(.seconds(Constants.setupDeadlineSeconds)) { [remoteConfigManager] in
                async let chainsReady: Void = chainRegistry.asyncWaitChainsSetup(for: [
                    AppConfig.Chains.usernameChain,
                    AppConfig.Chains.bulletInChain,
                    AppConfig.Chains.assethubChain
                ])
                _ = try? await (chainsReady, remoteConfigManager.asyncWaitRemoteConfig())
            }
            return .ready
        } catch {
            // Timeout or cancellation both stop startup; the caller's cancellation guard runs
            // before the outcome is acted on. Any unexpected error must not read as ready.
            return .deadlineExpired
        }
    }

    @MainActor
    private func completeSetup() {
        reevaluate()
    }

    @MainActor
    private func reportSetupFailure(kind: RootSetupFailureKind) {
        presenter?.didFailSetup(kind: kind)
    }
}

extension RootInteractor: RootInteractorInputProtocol {
    func reevaluate() {
        let destination = (try? resolver.resolve()) ?? .broken
        handleEstablishedUserIfNeeded(for: destination)
        prewarmProducts(for: destination)
        presenter?.didDecide(destination: destination)
    }

    func setup() {
        runMigrators()
        let chainRegistry = chainRegistryClosure()
        performCommonSetup(with: chainRegistry)

        #if TESTNET_FEATURE
            appFactoryResetChecker = appFactoryResetCheckerFactory?
                .makeChecker(chainRegistry: chainRegistry)
        #endif
    }

    func retrySetup() {
        let chainRegistry = chainRegistryClosure()
        performCommonSetup(with: chainRegistry)
    }

    func completeWalletsCreation() {
        reevaluate()
    }

    func completeWalletsRecovery() {
        reevaluate()
    }
}

private extension RootInteractor {
    func handleEstablishedUserIfNeeded(for destination: RootDestination) {
        guard destination.impliesEstablishedUser, !didReportEstablishedUser else {
            return
        }

        didReportEstablishedUser = true
        logWallets()

        #if TESTNET_FEATURE
            scheduleFactoryResetCheck()
        #endif
    }
}

#if TESTNET_FEATURE
    private extension RootInteractor {
        func scheduleFactoryResetCheck() {
            appFactoryResetChecker?.checkIfResetNeeded { [logger, presenter] resetNeeded in
                Task { @MainActor in
                    guard resetNeeded else { return }
                    guard let presenter else {
                        logger.error("Failed to present app reset alert")
                        return
                    }
                    presenter.didRequireAppFactoryReset()
                }
            }
        }
    }
#endif

private extension RootInteractor {
    func logWallets() {
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        let main = try? walletRepo.main().getRawPublicKey().toAddress(using: .genericFormat)
        let candidate = try? walletRepo.candidate().getRawPublicKey().toAddress(using: .genericFormat)
        let score = try? walletRepo.scoreAlias().getRawPublicKey().toAddress(using: .genericFormat)
        let mobRule = try? walletRepo.mobRuleAlias().getRawPublicKey().toAddress(using: .genericFormat)
        let resources = try? walletRepo.resourcesAlias().getRawPublicKey().toAddress(using: .genericFormat)

        logger.debug("Main address: \(main ?? "")")
        logger.debug("Candidate address: \(candidate ?? "")")
        logger.debug("Score address: \(score ?? "")")
        logger.debug("Mob rule address: \(mobRule ?? "")")
        logger.debug("Resources address: \(resources ?? "")")
    }
}

private extension RootInteractor {
    func startPathMonitoringIfNeeded() {
        guard pathTask == nil else {
            return
        }

        let stream = pathMonitor.pathStream()

        pathTask = Task { [weak self] in
            do {
                for try await isAvailable in stream {
                    self?.isPathSatisfied.withLock { $0 = isAvailable }
                }
            } catch {}
        }
    }

    /// Connectivity outranks every other cause: an unsatisfied path is the only thing the user can act on.
    func classifyFailure(fallback kind: RootSetupFailureKind) -> RootSetupFailureKind {
        isPathSatisfied.withLock { $0 } ? kind : .connectivity
    }
}
