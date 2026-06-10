import Foundation
import Products
import SubstrateSdk
import UIKitExt

/// A chat extension bot that delegates all behavior to a JavaScript product script.
///
/// The JS script controls:
/// - Welcome messages (via `onBotStarted`)
/// - Responses to user messages (via `onUserMessage`)
/// - Custom UI rendering (via `chatRenderWidget` / `chatSendCustomMessage`)
///
/// This bot just provides the bridge for JS to send messages to the chat.
/// Each instance is created by ``ProductBotFactory`` for a specific ``Product``.
final class ProductBot: ChatExtensionBot {
    let product: Product
    private let scriptExecutor: ProductsScriptExecutorProtocol
    private let nativeApiFactory: ProductsNativeApiMaking
    private let signingRouter: ProductsSigningRouter
    private let permissionRouter: ProductPermissionRouter
    private let topUpRequestRouter: TopUpRequestRouter
    private let paymentRequestRouter: PaymentRequestRouter
    private let logger: LoggerProtocol

    private var initTask: Task<Void, Never>?

    lazy var messageDecoder = ProductMessageDecoder(
        scriptExecutor: scriptExecutor,
        tokenResolver: WidgetDesignTokenResolver(),
        logger: logger
    )

    init(
        product: Product,
        scriptExecutor: ProductsScriptExecutorProtocol,
        nativeApiFactory: ProductsNativeApiMaking,
        signingRouter: ProductsSigningRouter = ProductsSigningRouter(),
        permissionRouter: ProductPermissionRouter = ProductPermissionRouter(),
        topUpRequestRouter: TopUpRequestRouter = TopUpRequestRouter(),
        paymentRequestRouter: PaymentRequestRouter = PaymentRequestRouter(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.product = product
        self.scriptExecutor = scriptExecutor
        self.nativeApiFactory = nativeApiFactory
        self.signingRouter = signingRouter
        self.permissionRouter = permissionRouter
        self.topUpRequestRouter = topUpRequestRouter
        self.paymentRequestRouter = paymentRequestRouter
        self.logger = logger
    }

    deinit {
        initTask?.cancel()
    }

    // MARK: - ChatExtensionBot

    override func onTextMessage(
        _ message: Chat.LocalMessage,
        text: String,
        context _: ChatExtensionProcessingContextProtocol
    ) async -> ChatExtension.ProcessingResult {
        do {
            try await scriptExecutor.onUserMessage(text: text, roomId: message.chatId.roomId)
        } catch {
            logger.error("Failed to forward user message to script: \(error)")
        }

        return .processed
    }

    /// Tear down the JS engine and cancel background work.
    func dispose() async {
        initTask?.cancel()
        initTask = nil
        await scriptExecutor.dispose()
        logger.debug("Disposed product bot: \(product.name)")
    }
}

// MARK: - ChatExtensionBotProtocol

extension ProductBot: ChatExtensionBotProtocol {
    var identifier: ChatExtension.Id {
        product.extensionId
    }

    var customDecoders: [ChatMessageCustomDecoding] {
        [messageDecoder]
    }

    var peerMetadata: Chat.PeerMetadata {
        Chat.PeerMetadata(
            name: product.name,
            contactSource: .chat,
            icon: .image(nil),
            input: .inputField(.init(canPay: false, canAttachFile: false)),
            moreActions: []
        )
    }

    func deliverAutomaticMessages(_ context: ChatExtensionDiscoverContextProtocol) {
        initTask = Task { [weak self] in
            guard let self else { return }

            let nativeApi = nativeApiFactory.makeApi(
                messagingSupport: .init(bot: self, context: context),
                productId: product.name,
                signingRouter: signingRouter,
                navigationRouter: ForbiddenNavigationRouter(),
                permissionRouter: permissionRouter,
                topUpRequestRouter: topUpRequestRouter,
                paymentRequestRouter: paymentRequestRouter
            )

            do {
                try await scriptExecutor.initializeBot(nativeApi: nativeApi)
                try await scriptExecutor.onBotStarted()
                logger.debug("Initialized and started bot: \(product.name)")
            } catch {
                logger.error("Failed to start product bot \(product.name): \(error)")
            }
        }
    }

    func process(action: Chat.Action, context: ChatExtensionActionContextProtocol) async {
        switch action {
        case let .customMessage(actionId, payload, messageId):
            let roomId = await (try? context.getMessage(messageId: messageId))?.chatId.roomId

            await scriptExecutor.dispatchEvent(
                roomId: roomId,
                messageId: messageId,
                actionId: actionId,
                payload: payload as? String
            )
        }
    }

    func attach(presentationView view: ControllerBackedProtocol) {
        Task { @MainActor in
            signingRouter.setPresentationView(view)
            permissionRouter.setPresentationView(view)
            topUpRequestRouter.setPresentationView(view)
            paymentRequestRouter.setPresentationView(view)
        }
    }
}
