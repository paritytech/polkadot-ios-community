import Foundation
import StatementStore
import ChainRegistry
import ChainStore
import Individuality
import KeyDerivation
import IssueMonitoring
import Products
import SubstrateSdk

protocol ActiveInstallationServiceMaking {
    func makeService() -> ActiveInstallationServicing
    func makeConfiguration() throws -> ActiveInstallationConfiguration
}

/// Every screen that follows the active installation record builds its own service; only one of them is on screen
/// at a time, and all of them save to the same store.
struct ActiveInstallationServiceFactory {
    let statusStore: InstallationStatusStoring
    let logger: LoggerProtocol
    var stopDiagnostic: IssueDiagnostic = DeviceTransferIssueDiagnostics.makeDefault().installationStopped
}

extension ActiveInstallationServiceFactory: ActiveInstallationServiceMaking {
    func makeService() -> ActiveInstallationServicing {
        var publishSettings = ActiveInstallationPublishSettings(deviceInfo: .current())
        publishSettings.stopDiagnostic = stopDiagnostic

        return ActiveInstallationService(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(entropyManager: RootEntropyManager.shared),
            installationProvider: CoinageCurrentInstallationProvider(
                repository: CoinageCurrentInstallationCoreDataRepository(storageFacade: UserDataStorageFacade.shared)
            ),
            publishSettings: publishSettings,
            statusStore: statusStore,
            logger: logger
        )
    }

    func makeConfiguration() throws -> ActiveInstallationConfiguration {
        let registry = ChainRegistryFacade.sharedRegistry
        let chainId = AppConfig.Chains.chatChain
        let statementsConnection = try StatementStoreConnection(
            connection: registry.getConnectionOrError(for: chainId),
            retryMatcher: StatementSubmitErrorMatcher.retryWhenTimeoutOrNoAllowance(),
            logger: logger
        )
        let signer = try ChatSignerManager().makeSigner(for: Chat.Contact.Own.main().signKeyId)

        return try ActiveInstallationConfiguration(
            connection: statementsConnection,
            signer: signer,
            lightPerson: makeLightPersonMembership(chainId: chainId, registry: registry)
        )
    }
}

private extension ActiveInstallationServiceFactory {
    func makeLightPersonMembership(chainId: ChainId, registry: ChainRegistryProtocol) throws -> LightPersonMembership {
        let tld = try DotNsTldProviderFacade.shared.currentTldOrError()
        let subscriber = try ChainMembershipSubscriber(
            connection: registry.getRpcConnectionOrError(for: chainId),
            runtimeCodingService: registry.getRuntimeCodingServiceOrError(for: chainId)
        )

        return try LightPersonMembership(
            waiter: MembershipStatusWaiter(subscriber: subscriber),
            input: MembershipStatusInput(
                memberKey: BandersnatchKeyManager.litePerson(for: tld).getMemberKey(),
                collection: PeopleLitePallet.membersIdentifier
            )
        )
    }
}
