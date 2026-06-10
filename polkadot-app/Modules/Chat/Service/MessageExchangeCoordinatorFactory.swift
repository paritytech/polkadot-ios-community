import Foundation
import UniqueDevice
import MessageExchangeKit
import SubstrateSdk
import NovaCrypto
import KeyDerivation
import Products

protocol MessageExchangeCoordinatorMaking {
    func makeChatCoordinator() throws -> MessageExchangeChatCoordinating
    func makeSignInHostCoordinator(
        accountManager: ProductsAccountManaging,
        sponsorFactory: TransactionSponsorMaking
    ) throws -> MessageExchangeSignInHostCoordinating
}

final class MessageExchangeCoordinatorFactory {
    private let entropyManager: RootEntropyManaging
    private let storageFacade: StorageFacadeProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    init(
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.entropyManager = entropyManager
        self.storageFacade = storageFacade
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension MessageExchangeCoordinatorFactory: MessageExchangeCoordinatorMaking {
    enum Constants {
        static let maxChatStatementSize = 500 * 1_024
        static let maxSSOStatementSize = 500 * 1_024
        static let maxDeviceSyncStatementSize = 500 * 1_024
    }

    func makeChatCoordinator() throws -> MessageExchangeChatCoordinating {
        let encryptionManager = ChatEncryptionManager(
            entropyManager: entropyManager
        )

        let signerManager = ChatSignerManager(entropyManager: entropyManager)

        let pushIdFactory = ChatPushIdFactory(
            encryptionManager: encryptionManager,
            signManager: signerManager,
            sessionIdFactory: PeerSessionIdFactory(),
            logger: logger
        )

        let tokenProvider = JWTTokenManager.shared
        let deviceKeyManager = DeviceEncryptionKeyManager.shared
        let messageExchangeModeProvider = ChatMessageExchangeModeProvider()

        return try MessageExchangeChatCoordinator(
            serviceFactory: MessageExchangeServiceFactory(
                messageExchangeModeProvider: messageExchangeModeProvider,
                entropyManager: entropyManager,
                deviceEncryptionKeyFactory: MultideviceComponentFactory.makeDeviceEncryptionKeyFactory(
                    deviceEncryptionKeyManager: deviceKeyManager
                ),
                maxStatementSize: Constants.maxChatStatementSize,
                operationQueue: operationQueue,
                logger: logger
            ),
            pushIdFactory: pushIdFactory,
            pushMessageCoder: ChatPushMessageCoder(encryptionManager: encryptionManager),
            chatRequestStoreService: ChatRequestStoreService(
                messageExchangeModeProvider: messageExchangeModeProvider,
                storageFacade: storageFacade,
                pushIdFactory: pushIdFactory,
                deviceEncryptionKeyManager: deviceKeyManager
            ),
            tokenProvider: tokenProvider,
            chatContactDataProviderFactory: ChatContactDataProviderFactory(
                repositoryFactory: ChatContactRepositoryFactory(storageFacade: storageFacade),
                operationQueue: operationQueue,
                logger: logger
            ),
            messageExchangeModeProvider: messageExchangeModeProvider
        )
    }

    func makeSignInHostCoordinator(
        accountManager: ProductsAccountManaging,
        sponsorFactory: TransactionSponsorMaking
    ) -> MessageExchangeSignInHostCoordinating {
        MessageExchangeSignInHostCoordinator(
            ownKeyId: Chat.Contact.Own.sso(),
            serviceFactory: MessageExchangeServiceFactory(
                messageExchangeModeProvider: FixedMessageExchangeModeProvider(mode: .identity),
                entropyManager: entropyManager,
                deviceEncryptionKeyFactory: nil,
                maxStatementSize: Constants.maxSSOStatementSize,
                operationQueue: operationQueue,
                logger: logger
            ),
            accountManager: accountManager,
            sponsorFactory: sponsorFactory
        )
    }
}
