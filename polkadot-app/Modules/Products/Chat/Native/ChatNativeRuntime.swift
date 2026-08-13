import Foundation
import Products
import UIKitExt

/// Native chat runtime: requests handled by Swift (ContainerBridge +
/// ProductsNativeApi). Wraps the pristine ProductsScriptExecutor with the
/// exact wiring ProductBotFactory used inline before this refactor.
///
/// @unchecked Sendable: immutable wiring only — all mutable state lives
/// inside the ProductsScriptExecutor actor.
final class ChatNativeRuntime: ChatRuntimeProtocol, @unchecked Sendable {
    private let productId: ProductId
    private let scriptExecutor: ProductsScriptExecutorProtocol
    private let nativeApiFactory: ProductsNativeApiMaking
    private let routers: ProductRoutersFacadeProtocol

    init(
        productId: ProductId,
        scriptExecutor: ProductsScriptExecutorProtocol,
        nativeApiFactory: ProductsNativeApiMaking,
        routers: ProductRoutersFacadeProtocol
    ) {
        self.productId = productId
        self.scriptExecutor = scriptExecutor
        self.nativeApiFactory = nativeApiFactory
        self.routers = routers
    }

    func start(messagingSupport: ProductsNativeApi.MessagingSupport) async throws {
        let nativeApi = nativeApiFactory.makeApi(
            messagingSupport: messagingSupport,
            productId: productId,
            routers: routers
        )

        try await scriptExecutor.initializeBot(nativeApi: nativeApi)
        try await scriptExecutor.onBotStarted()
    }

    func onUserMessage(text: String, roomId: String?) async throws {
        try await scriptExecutor.onUserMessage(text: text, roomId: roomId)
    }

    func renderMessage(
        messageId: String,
        messageType: String,
        messageData: Data
    ) async -> AsyncThrowingStream<String, Error> {
        await scriptExecutor.renderMessage(
            messageId: messageId,
            messageType: messageType,
            messageData: messageData
        )
    }

    func dispatchEvent(roomId: String?, messageId: String, actionId: String, payload: String?) async {
        await scriptExecutor.dispatchEvent(
            roomId: roomId,
            messageId: messageId,
            actionId: actionId,
            payload: payload
        )
    }

    @MainActor
    func attach(presentationView view: ControllerBackedProtocol) {
        routers.setPresentationView(view)
    }

    func dispose() async {
        await scriptExecutor.dispose()
    }
}
