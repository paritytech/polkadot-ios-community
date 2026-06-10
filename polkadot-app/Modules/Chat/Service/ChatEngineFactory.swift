import Foundation
import MessageExchangeKit
import Keystore_iOS

protocol ChatEngineFactoryProtocol {
    func createChatEngine(for model: ChatOpenModel.NewRequest) -> ChatEngineProtocol
    func createChatEngine(for model: Chat.Id) -> ChatEngineProtocol
}

final class ChatEngineFactory: ChatEngineFactoryProtocol {
    let flowState: ChatFlowState
    init(flowState: ChatFlowState) {
        self.flowState = flowState
    }

    func createChatEngine(for model: Chat.Id) -> any ChatEngineProtocol {
        createChatEngine(for: nil, chatId: model)
    }

    func createChatEngine(for model: ChatOpenModel.NewRequest) -> any ChatEngineProtocol {
        let chatId = Chat.Id.person(model.remoteContact.accountId)
        return createChatEngine(for: model, chatId: chatId)
    }

    private func createChatEngine(
        for request: ChatOpenModel.NewRequest?,
        chatId: Chat.Id
    ) -> any ChatEngineProtocol {
        let chatIdFactory = ChatPushIdFactory(
            encryptionManager: ChatEncryptionManager(),
            signManager: ChatSignerManager(),
            sessionIdFactory: PeerSessionIdFactory(),
            logger: Logger.shared
        )

        let storageFacade = UserDataStorageFacade.shared
        let messageExchangeModeProvider = ChatMessageExchangeModeProvider()
        let leaveChatService = LeaveChatService(
            outboxService: flowState.outboxService,
            messageExchangeModeProvider: messageExchangeModeProvider
        )
        let blockUserService = BlockUserService()

        let requestContext = ChatRequestEngineContext(
            pendingRequest: request,
            chatRequestStoreService: ChatRequestStoreService(
                messageExchangeModeProvider: messageExchangeModeProvider,
                storageFacade: storageFacade,
                pushIdFactory: chatIdFactory,
                deviceEncryptionKeyManager: DeviceEncryptionKeyManager.shared
            ),
            messageExchangeModeProvider: messageExchangeModeProvider,
            tokenProvider: APNSTokenProviderFacade.sharedManager,
            storageFacade: storageFacade
        )

        return ChatEngine(
            chatId: chatId,
            chatRequestContext: requestContext,
            chatExtensionRegistry: flowState.extensionsRegistry,
            messageProviderFactory: ChatMessageDataProviderFactory(),
            chatProvider: ChatContactDataProviderFactory(),
            settings: SettingsManager.shared,
            leaveChatService: leaveChatService,
            blockUserService: blockUserService
        )
    }
}
