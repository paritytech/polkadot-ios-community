@testable import polkadot_app
import XCTest
import Keystore_iOS
import NovaCrypto
import SubstrateSdk
import Operation_iOS
import ExtrinsicService
import KeyDerivation
import Individuality
import SDKLogger
import SubstrateStorageQuery
import Products

final class StatementStoreSlotAllocatorTests: XCTestCase {
    private let mnemonic = "city digital broken voice chef envelope swarm disagree claw fox friend casual"

    func testAssignSlotOnChain() async throws {
        let setupResult = try setupWallet()
        let storageFacade = SubstrateStorageTestFacade()
        let operationQueue = OperationQueue()

        let chainRegistry = ChainRegistryFacade.setupForIntegrationTest(
            with: storageFacade,
            logger: Logger.shared
        )

        let storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        let liteVrfManager = BandersnatchKeyManager.litePerson(entropyManager: setupResult.entropyManager)
        let fullVrfManager = BandersnatchKeyManager.fullPerson(entropyManager: setupResult.entropyManager)

        let keyResolver = BandersnatchKeyResolver(
            liteKeyManager: liteVrfManager,
            fullKeyManager: fullVrfManager
        )

        let originFactory = AsResourcesOriginFactory(
            wallet: setupResult.wallet,
            keyResolver: keyResolver,
            chainRegistry: chainRegistry
        )

        let facade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: storageFacade,
            operationQueue: operationQueue,
            logger: Logger.shared
        )

        let chain = try chainRegistry.getChainOrError(for: KnownChainId.previewNetPeople)
        let monitorFactory = try facade.createMonitorFactory(chain: chain)

        let slotInfoProvider = StatementStoreSlotInfoProvider(
            chainId: KnownChainId.previewNetPeople,
            chainRegistry: chainRegistry,
            storageRequestFactory: storageRequestFactory,
            keyResolver: keyResolver,
            logger: MockLogger()
        )

        let allocator = StatementStoreSlotAllocator(
            chainId: KnownChainId.previewNetPeople,
            originFactory: originFactory,
            submitter: SlotAssignmentSubmitter(monitorFactory: monitorFactory),
            slotInfoProvider: slotInfoProvider
        )

        let holder = ProductAccountHolder(entropyManager: setupResult.entropyManager)
        let accountId = try holder.deriveAccount(ProductAccountId(productId: "browse.dot", derivationIndex: 0))

        try await allocator.assignSlot(accountId: accountId)
    }
}

// MARK: - Wallet Setup

private extension StatementStoreSlotAllocatorTests {
    struct WalletSetup {
        let wallet: WalletManaging
        let entropyManager: RootEntropyManaging
    }

    func setupWallet() throws -> WalletSetup {
        let keychain = InMemoryKeychain()
        let entropyManager = RootEntropyManager(keychain: keychain, userDefaults: UserDefaults.standard)
        let manager = WalletSetupManager(
            mnemonicGenerator: IRMnemonicCreator(),
            mnemonicBackupHelper: MockMnemonicBackupHelper(),
            entropyManager: entropyManager,
            logger: Logger.shared
        )
        let mnemonicObj = try IRMnemonicCreator().mnemonic(fromList: mnemonic)
        try manager.createWallets(with: .init(mnemonic: mnemonicObj))
        return WalletSetup(
            wallet: DynamicDerivedWallet(derivationPath: "//wallet", entropyManager: entropyManager),
            entropyManager: entropyManager
        )
    }
}
