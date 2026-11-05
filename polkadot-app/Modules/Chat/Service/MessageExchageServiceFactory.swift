import Foundation
import SubstrateSdk
import Keystore_iOS
import MessageExchangeKit
import StatementStore
import NovaCrypto
import KeyDerivation

protocol MessageExchageServiceMaking {
    /// `statementSignerResolver` picks the account that signs the sessions' statements.
    func makeService<M: MessageExchange.CodableMessage>(
        statementStoreConnection: StatementStoreConnecting,
        statementSignerResolver: PeerSessionSignerResolving,
        delegate: AnyPeerSessionDelegate<M>,
        compactorFactory: AnyMessageCompactorFactory<M>?
    ) throws -> AnyMessageExchangeService<M>
}

extension MessageExchageServiceMaking {
    func makeService<M: MessageExchange.CodableMessage>(
        statementStoreConnection: StatementStoreConnecting,
        statementSignerResolver: PeerSessionSignerResolving,
        delegate: AnyPeerSessionDelegate<M>
    ) throws -> AnyMessageExchangeService<M> {
        try makeService(
            statementStoreConnection: statementStoreConnection,
            statementSignerResolver: statementSignerResolver,
            delegate: delegate,
            compactorFactory: nil
        )
    }
}

final class MessageExchangeServiceFactory {
    let signManager: StatementStoreSignerManaging
    let encryptionManager: MessageExchangeEncryptionManaging
    let deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?
    let messageExchangeModeProvider: MessageExchangeModeProviding
    let workQueue: DispatchQueue
    let operationQueue: OperationQueue
    let maxStatementSize: Int
    let accountProvider: PeerSessionAccountProviding
    let priorityFactory: StatementPriorityMaking
    let logger: LoggerProtocol

    init(
        messageExchangeModeProvider: MessageExchangeModeProviding,
        signManager: StatementStoreSignerManaging,
        encryptionManager: MessageExchangeEncryptionManaging,
        deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?,
        maxStatementSize: Int,
        accountProvider: PeerSessionAccountProviding,
        priorityFactory: StatementPriorityMaking = StatementPriorityFactory(),
        workQueue: DispatchQueue = DispatchQueue(label: "message.exchange.work.queue"),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.signManager = signManager
        self.accountProvider = accountProvider
        self.priorityFactory = priorityFactory
        self.encryptionManager = encryptionManager
        self.deviceEncryptionKeyFactory = deviceEncryptionKeyFactory
        self.messageExchangeModeProvider = messageExchangeModeProvider
        self.workQueue = workQueue
        self.operationQueue = operationQueue
        self.maxStatementSize = maxStatementSize
        self.logger = logger
    }

    convenience init(
        messageExchangeModeProvider: MessageExchangeModeProviding,
        entropyManager: RootEntropyManaging,
        deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?,
        maxStatementSize: Int,
        workQueue: DispatchQueue = DispatchQueue(label: "message.exchange.work.queue"),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        let signManager = ChatSignerManager(entropyManager: entropyManager)

        self.init(
            messageExchangeModeProvider: messageExchangeModeProvider,
            signManager: signManager,
            encryptionManager: ChatEncryptionManager(entropyManager: entropyManager),
            deviceEncryptionKeyFactory: deviceEncryptionKeyFactory,
            maxStatementSize: maxStatementSize,
            accountProvider: SignerSessionAccountProvider(signerManager: signManager),
            workQueue: workQueue,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension MessageExchangeServiceFactory: MessageExchageServiceMaking {
    func makeService<M: MessageExchange.CodableMessage>(
        statementStoreConnection: StatementStoreConnecting,
        statementSignerResolver: PeerSessionSignerResolving,
        delegate: AnyPeerSessionDelegate<M>,
        compactorFactory: AnyMessageCompactorFactory<M>?
    ) throws -> AnyMessageExchangeService<M> {
        let subscriptionFactory = StatementSubscriptionFactory(
            statementStoreFetcher: statementStoreConnection,
            workQueue: workQueue,
            operationQueue: operationQueue,
            logger: logger
        )

        let sessionFactory = PeerSessionFactory<M>(
            delegate: delegate,
            workQueue: workQueue,
            statementSignerResolver: statementSignerResolver,
            statementStoreConnection: statementStoreConnection,
            encryptionManager: encryptionManager,
            deviceEncryptionKeyFactory: deviceEncryptionKeyFactory,
            messageExchangeModeProvider: messageExchangeModeProvider,
            accountProvider: accountProvider,
            sessionIdFactory: PeerSessionIdFactory(),
            channelFactory: ChatStatementChannelFactory(),
            preSendHandler: AnyPeerSessionPreSendHandler.empty(),
            subscriptionFactory: subscriptionFactory,
            maxStatementSize: maxStatementSize,
            priorityFactory: priorityFactory,
            compactorFactory: compactorFactory,
            operationQueue: operationQueue,
            logger: logger
        )

        let sessionManager = PeerSessionManager(
            sessionFactory: AnyPeerSessionFactory(sessionFactory),
            workQueue: workQueue,
            logger: logger
        )

        let messageExchangeService = MessageExchangeService(
            sessionManager: AnyPeerSessionManager(sessionManager)
        )

        return AnyMessageExchangeService(messageExchangeService)
    }
}
