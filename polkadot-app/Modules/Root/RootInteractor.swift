import Foundation
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

    weak var presenter: RootInteractorOutputProtocol?

    let chainRegistryClosure: ChainRegistryLazyClosure

    let migrator: Migrating
    let logger: LoggerProtocol
    let resolver: any DecisionResolver<RootDestination>
    let tokenManager: JWTTokenManaging
    let tldProvider: DotNsTldProviding

    let remoteConfigManager: RemoteConfigManaging
    let chainRegistryConfigurator: ChainRegistryConfiguring
    let browsePrewarmer: ProductContentPrewarming

    private let setupDeadlineSeconds: TimeInterval = 10
    private var completionTask: Task<Void, Never>?
    private var didReportEstablishedUser = false

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
        browsePrewarmer: ProductContentPrewarming,
        tldProvider: DotNsTldProviding = DotNsTldProviderFacade.shared
    ) {
        self.chainRegistryClosure = chainRegistryClosure

        self.migrator = migrator
        self.logger = logger
        self.resolver = resolver
        self.tokenManager = tokenManager
        self.remoteConfigManager = remoteConfigManager
        self.chainRegistryConfigurator = chainRegistryConfigurator
        self.browsePrewarmer = browsePrewarmer
        self.tldProvider = tldProvider
    }

    deinit {
        completionTask?.cancel()
    }

    @MainActor
    private func performCommonSetup(with chainRegistry: ChainRegistryProtocol) {
        completionTask?.cancel()

        setupChainUpdate(for: chainRegistry)
        fetchRemoteConfig()

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
            browsePrewarmer.prewarm()
        default:
            break
        }
    }

    private func startSetupCompletionTask(for chainRegistry: ChainRegistryProtocol) {
        completionTask = Task { [weak self, remoteConfigManager, tldProvider] in
            await self?.performSetupCompletion(
                for: chainRegistry,
                remoteConfigManager: remoteConfigManager,
                tldProvider: tldProvider
            )
        }
    }

    private func performSetupCompletion(
        for chainRegistry: ChainRegistryProtocol,
        remoteConfigManager: RemoteConfigManaging,
        tldProvider: DotNsTldProviding
    ) async {
        let outcome = await waitForSetupInputs(
            for: chainRegistry,
            remoteConfigManager: remoteConfigManager
        )

        guard !Task.isCancelled else { return }

        if outcome == .deadlineExpired {
            await reportSetupFailure()
            return
        }

        setupJWTManager()

        // Cache the DotNs TLD once chains and remote config are ready. Resolving here covers
        // every onboarding path (username claim, iCloud recovery), so downstream built-in
        // account derivation can read the TLD synchronously. A TLD persisted by a previous
        // run is enough, so startup is not blocked offline; currentTld() kicks a background
        // refresh on its own.
        if tldProvider.currentTld() == nil {
            do {
                _ = try await withRetry(
                    maxAttempts: 4,
                    initialDelay: .seconds(1)
                ) {
                    try await tldProvider.resolveTld()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await reportSetupFailure()
                return
            }
        }

        guard !Task.isCancelled else { return }

        await completeSetup()
    }

    /// Waits for the paired chain registry and remote config, bounded by ``setupDeadlineSeconds``.
    /// A chain or remote config failure is not fatal on its own: only the deadline gates startup.
    private func waitForSetupInputs(
        for chainRegistry: ChainRegistryProtocol,
        remoteConfigManager: RemoteConfigManaging
    ) async -> SetupWaitOutcome {
        do {
            try await withTimeout(.seconds(setupDeadlineSeconds)) {
                async let chainsReady: Void = chainRegistry.asyncWaitChainsSetup(for: [
                    AppConfig.Chains.usernameChain,
                    AppConfig.Chains.bulletInChain,
                    AppConfig.Chains.assethubChain
                ])
                _ = try? await (chainsReady, remoteConfigManager.asyncWaitRemoteConfig())
            }
            return .ready
        } catch is TimeoutError {
            return .deadlineExpired
        } catch {
            // The enclosing task was cancelled, so the deadline did not expire. The caller's
            // cancellation guard stops the flow before this outcome is acted on.
            return .ready
        }
    }

    @MainActor
    private func completeSetup() {
        reevaluate()
    }

    @MainActor
    private func reportSetupFailure() {
        presenter?.didFailSetup()
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
