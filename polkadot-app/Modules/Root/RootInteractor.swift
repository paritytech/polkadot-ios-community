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
import EventCenter

final class RootInteractor {
    private enum SetupWaitOutcome {
        case ready
        case deadlineExpired
        case configurationBroken
    }

    private struct PathState {
        var isSatisfied = true
        var isAwaitingRecovery = false
    }

    private struct SetupDeadlineExpired: Error {}

    private enum Constants {
        static let setupDeadlineSeconds: TimeInterval = 10
        /// Applied when the path is already unsatisfied: locally-served chains and a cached config
        /// still resolve well inside it, so only a genuinely blocked wait is cut short.
        static let offlineSetupDeadlineSeconds: TimeInterval = 3
        static let tldTimeoutSeconds: TimeInterval = 10
        static let tldRetryMaxAttempts = 4
        static let tldRetryInitialDelay: Duration = .seconds(1)
    }

    private static let requiredChainIds: Set<ChainModel.Id> = [
        AppConfig.Chains.usernameChain,
        AppConfig.Chains.bulletInChain,
        AppConfig.Chains.assethubChain
    ]

    weak var presenter: RootInteractorOutputProtocol?

    let chainRegistryClosure: ChainRegistryLazyClosure

    let migrator: Migrating
    let logger: LoggerProtocol
    let resolver: any DecisionResolver<RootDestination>
    let tokenManager: JWTTokenManaging
    let eventCenter: EventCenterProtocol
    let tldProvider: DotNsTldProviding

    let remoteConfigManager: RemoteConfigManaging
    let chainRegistryConfigurator: ChainRegistryConfiguring
    let productPrewarmer: ProductContentPrewarming
    let pathMonitor: NetworkPathMonitoring

    private var completionTask: Task<Void, Never>?
    private var didReportEstablishedUser = false
    private let pathState = OSAllocatedUnfairLock(initialState: PathState())
    private var pathTask: Task<Void, Never>?
    private let didReportOutcome = OSAllocatedUnfairLock(initialState: false)
    private var didRegisterForEvents = false

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
        eventCenter: EventCenterProtocol,
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
        self.eventCenter = eventCenter
        self.remoteConfigManager = remoteConfigManager
        self.chainRegistryConfigurator = chainRegistryConfigurator
        self.productPrewarmer = productPrewarmer
        self.pathMonitor = pathMonitor
        self.tldProvider = tldProvider
    }

    deinit {
        completionTask?.cancel()
        pathTask?.cancel()
        eventCenter.remove(observer: self)
    }

    @MainActor
    private func performCommonSetup(with chainRegistry: ChainRegistryProtocol) {
        completionTask?.cancel()
        didReportOutcome.withLock { $0 = false }

        setupChainUpdate(for: chainRegistry)
        fetchRemoteConfig()
        startPathMonitoringIfNeeded()
        registerForEventCenterIfNeeded()

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

        switch outcome {
        case .ready:
            break
        case .deadlineExpired:
            guard claimOutcome() else { return }
            await reportSetupFailure(kind: classifyFailure(fallback: .unknown))
            return
        case .configurationBroken:
            guard claimOutcome() else { return }
            await reportSetupFailure(kind: classifyFailure(fallback: .configuration(.config)))
            return
        }

        setupJWTManager()

        do {
            try await resolveTldIfNeeded()
        } catch {
            guard !Task.isCancelled else { return }
            guard claimOutcome() else { return }
            await reportSetupFailure(kind: classifyFailure(fallback: .unknown))
            return
        }

        guard !Task.isCancelled else { return }

        guard claimOutcome() else { return }
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

    /// Waits for the paired chain registry and remote config, bounded by the full deadline,
    /// cut to the offline deadline when the path is unsatisfied once that shorter deadline
    /// is reached; a chain or remote config failure is not fatal on its own.
    private func waitForSetupInputs(for chainRegistry: ChainRegistryProtocol) async -> SetupWaitOutcome {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [remoteConfigManager] in
                    async let chainsReady: Void = chainRegistry
                        .asyncWaitChainsSetup(for: Self.requiredChainIds)
                    do {
                        _ = try await (chainsReady, remoteConfigManager.asyncWaitRemoteConfig())
                    } catch {
                        // Only a broken remote config stops setup; chain and other failures
                        // stay non-fatal on their own and are swallowed here.
                        if error as? RemoteConfigError == .invalidConfig {
                            throw error
                        }
                    }
                }

                group.addTask {
                    try await self.enforceSetupDeadline()
                }

                _ = try await group.next()
                group.cancelAll()
            }

            return .ready
        } catch RemoteConfigError.invalidConfig {
            return .configurationBroken
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
    /// Setup can now finish from two places — the wait and the chain-sync event — so the first one
    /// to report wins and the other is dropped.
    func claimOutcome() -> Bool {
        didReportOutcome.withLock { reported in
            guard !reported else { return false }
            reported = true
            return true
        }
    }

    func registerForEventCenterIfNeeded() {
        guard !didRegisterForEvents else {
            return
        }

        didRegisterForEvents = true
        eventCenter.add(observer: self, dispatchIn: .main)
    }

    /// Observes network path transitions; both feeds failure classification and drives unattended retry after a
    /// connectivity failure.
    func startPathMonitoringIfNeeded() {
        guard pathTask == nil else {
            return
        }

        let stream = pathMonitor.pathStream()

        pathTask = Task { [weak self] in
            do {
                for try await isAvailable in stream {
                    guard let self else { return }
                    guard consumeRecovery(isAvailable: isAvailable) else { continue }

                    await MainActor.run { self.retrySetup() }
                }
            } catch {}
        }
    }

    /// Records the new satisfaction and reports whether it recovers a connectivity failure still awaiting
    /// retry, consuming the flag so one recovery drives at most one retry.
    func consumeRecovery(isAvailable: Bool) -> Bool {
        pathState.withLock { state in
            let isRecovery = isAvailable && !state.isSatisfied && state.isAwaitingRecovery
            state.isSatisfied = isAvailable
            if isRecovery {
                state.isAwaitingRecovery = false
            }
            return isRecovery
        }
    }

    /// Connectivity outranks every other cause: an unsatisfied path is the only thing the user can act on.
    func classifyFailure(fallback kind: RootSetupFailureKind) -> RootSetupFailureKind {
        pathState.withLock { state in
            guard !state.isSatisfied else { return kind }
            state.isAwaitingRecovery = true
            return .connectivity
        }
    }

    /// Ends the wait early when the path is unsatisfied at the offline deadline — by then the monitor has
    /// emitted, so the choice is made on a known value rather than a race with the first emission.
    func enforceSetupDeadline() async throws {
        try await Task.sleep(for: .seconds(Constants.offlineSetupDeadlineSeconds))

        if pathState.withLock({ $0.isSatisfied }) {
            let remaining = Constants.setupDeadlineSeconds - Constants.offlineSetupDeadlineSeconds
            try await Task.sleep(for: .seconds(remaining))
        }

        throw SetupDeadlineExpired()
    }
}

extension RootInteractor: ChainRegistryEventVisiting {
    func processChainSyncDidComplete(event: ChainSyncDidComplete) {
        let availableChainIds = Set(event.newOrUpdatedChains.map(\.chainId))
        guard !Self.requiredChainIds.isSubset(of: availableChainIds) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard claimOutcome() else { return }

            completionTask?.cancel()
            reportSetupFailure(kind: classifyFailure(fallback: .configuration(.chains)))
        }
    }
}
