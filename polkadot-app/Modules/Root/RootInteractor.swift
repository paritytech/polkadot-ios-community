import Foundation
import NovaCrypto
import Operation_iOS
import Foundation_iOS
import SubstrateSdk

final class RootInteractor {
    weak var presenter: RootInteractorOutputProtocol?

    let chainRegistryClosure: ChainRegistryLazyClosure

    let migrator: Migrating
    let logger: LoggerProtocol
    let resolver: any DecisionResolver<RootDestination>
    let tokenManager: JWTTokenManaging

    let firebaseFacade = FirebaseFacade.shared
    let browsePrewarmer: ProductContentPrewarming
    let web3SummitPrewarmer: ProductContentPrewarming

    private let setupTimeoutSeconds: TimeInterval = 5
    private var setupTimeoutTask: Task<Void, Never>?
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
        browsePrewarmer: ProductContentPrewarming,
        web3SummitPrewarmer: ProductContentPrewarming
    ) {
        self.chainRegistryClosure = chainRegistryClosure

        self.migrator = migrator
        self.logger = logger
        self.resolver = resolver
        self.tokenManager = tokenManager
        self.browsePrewarmer = browsePrewarmer
        self.web3SummitPrewarmer = web3SummitPrewarmer
    }

    deinit {
        setupTimeoutTask?.cancel()
    }

    private func setupChainUpdate(for registry: ChainRegistryProtocol) {
        firebaseFacade.set(chainRegistry: registry)
    }

    private func runMigrators() {
        do {
            try migrator.migrate()
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemoteConfig() {
        firebaseFacade.fetchRemoteConfigValues()
    }

    private func setupJWTManager() {
        let authProvider = AppAttestProviderResolver.resolve()

        tokenManager.setup(authProvider: authProvider)
        tokenManager.prewarm()
    }

    @MainActor
    private func prewarmProducts(for destination: RootDestination) {
        switch destination {
        case .onboarding,
             .restoreFromCloud:
            web3SummitPrewarmer.prewarm()
        case .dashboard:
            browsePrewarmer.prewarm()
        default:
            break
        }
    }

    private func completeSetupOnceRemoteConfig(from chainRegistry: ChainRegistryProtocol) {
        Task { [weak self, firebaseFacade] in
            async let chainsReady: Void = chainRegistry.asyncWaitChainsSetup(for: [
                AppConfig.Chains.usernameChain,
                AppConfig.Chains.bulletInChain
            ])
            async let remoteConfig = try firebaseFacade.asyncWaitRemoteConfig()
            _ = try? await (chainsReady, remoteConfig)

            self?.setupJWTManager()

            await self?.completeSetup()
        }
    }

    @MainActor
    private func completeSetup() {
        setupTimeoutTask?.cancel()
        reevaluate()
    }

    func startSetupTimeoutTask() {
        let timeout = setupTimeoutSeconds
        setupTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.presenter?.didExceedSetupTimeout()
        }
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
        startSetupTimeoutTask()

        let chainRegistry = chainRegistryClosure()
        setupChainUpdate(for: chainRegistry)
        fetchRemoteConfig()

        completeSetupOnceRemoteConfig(from: chainRegistry)

        #if TESTNET_FEATURE
            appFactoryResetChecker = appFactoryResetCheckerFactory?
                .makeChecker(chainRegistry: chainRegistry)
        #endif
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
        let main = try? SelectedWallet.main.getRawPublicKey().toAddress(using: .genericFormat)
        let candidate = try? SelectedWallet.candidate.getRawPublicKey().toAddress(using: .genericFormat)
        let score = try? SelectedWallet.scoreAlias.getRawPublicKey().toAddress(using: .genericFormat)
        let mobRule = try? SelectedWallet.mobRuleAlias.getRawPublicKey().toAddress(using: .genericFormat)
        let resources = try? SelectedWallet.resourcesAlias.getRawPublicKey().toAddress(using: .genericFormat)

        logger.debug("Main address: \(main ?? "")")
        logger.debug("Candidate address: \(candidate ?? "")")
        logger.debug("Score address: \(score ?? "")")
        logger.debug("Mob rule address: \(mobRule ?? "")")
        logger.debug("Resources address: \(resources ?? "")")
    }
}
