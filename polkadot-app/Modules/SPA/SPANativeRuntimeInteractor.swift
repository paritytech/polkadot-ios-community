import Foundation
import Operation_iOS
import Products
import AsyncExtensions

@MainActor
final class SPANativeRuntimeInteractor {
    weak var presenter: SPAInteractorOutputProtocol?

    private let nativeApi: ProductsNativeApiProtocol
    private let scriptsFactory: SPAScriptsMaking
    private let dotNsResolver: DotNsResolverProtocol
    private let schemeHandlerProxy: SchemeHandlerProxy
    private let configuration: SPAConfiguration
    private let logger: LoggerProtocol
    private let productRepository: AnyDataProviderRepository<Product>
    private let chatProviderFactory: ChatContactDataProviderMaking

    private var containerBridge: ContainerBridge?
    private var jsEngine: JSEngineProtocol?
    private var engineMonitor: JSEngineMonitor?

    private var setupTask: Task<Void, Never>?
    private var openChatTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    init(
        nativeApi: ProductsNativeApiProtocol,
        scriptsFactory: SPAScriptsMaking,
        dotNsResolver: DotNsResolverProtocol,
        schemeHandlerProxy: SchemeHandlerProxy,
        configuration: SPAConfiguration,
        logger: LoggerProtocol,
        productRepository: AnyDataProviderRepository<Product>,
        chatProviderFactory: ChatContactDataProviderMaking
    ) {
        self.nativeApi = nativeApi
        self.scriptsFactory = scriptsFactory
        self.dotNsResolver = dotNsResolver
        self.schemeHandlerProxy = schemeHandlerProxy
        self.configuration = configuration
        self.logger = logger
        self.productRepository = productRepository
        self.chatProviderFactory = chatProviderFactory
    }

    deinit {
        setupTask?.cancel()
        openChatTask?.cancel()
        progressTask?.cancel()

        engineMonitor?.stop()

        Task { [containerBridge, jsEngine] in
            await containerBridge?.dispose()
            await jsEngine?.destroy()
        }
    }
}

extension SPANativeRuntimeInteractor: SPAInteractorInputProtocol {
    func setup(engine: JSEngineProtocol) {
        jsEngine = engine
        setupTask = Task { [weak self] in
            await self?.performSetup(engine: engine)
        }
    }

    func retry() {
        guard let engine = jsEngine else { return }

        setupTask?.cancel()
        setupTask = Task { [weak self] in
            await self?.performSetup(engine: engine)
        }
    }

    func hasChatEntry() -> Bool {
        dotNsResolver.hasChatEntry(configuration.page.host.toDotDomain())
    }

    func openChat() {
        guard openChatTask == nil else {
            return
        }

        openChatTask = Task { [weak self] in
            do {
                guard let extensionId = try await self?.enableProduct() else {
                    return
                }

                if let chatId = try await self?.waitProductChat(for: extensionId) {
                    self?.presenter?.didPrepareChat(chatId: chatId)
                }
            } catch {
                self?.logger.error("SPA: Failed to open chat: \(error)")
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                self?.openChatTask = nil
            }
        }
    }
}

private extension SPANativeRuntimeInteractor {
    func enableProduct() async throws -> ChatExtension.Id {
        let product = Product(id: configuration.page.host.toDotDomain(), name: configuration.page.host.name)
        let extensionId = product.extensionId

        let existingProduct = try await productRepository
            .fetchOperation(by: { product.identifier }, options: RepositoryFetchOptions())
            .asyncExecute()

        if existingProduct == nil {
            try await productRepository.saveOperation({ [product] }, { [] }).asyncExecute()
        }

        return extensionId
    }

    func waitProductChat(for extensionId: ChatExtension.Id) async throws -> Chat.Id? {
        let stream = chatProviderFactory.subscribeChatsWithPredicate(.roomChatsForExtension(extensionId))

        for try await chats in stream {
            if let chat = chats.first {
                return chat.chatId
            }
        }

        return nil
    }

    func subscribeProgress(domain: String) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            guard let stream = self?.dotNsResolver.progressStream(dotNsName: domain) else { return }
            do {
                for try await progress in stream {
                    guard !Task.isCancelled else { return }
                    self?.presenter?.didUpdateLoadProgress(progress)
                }
            } catch {
                self?.logger.error("Resolve progress error: \(error)")
            }
        }
    }

    /// Cancellation guards after every await: teardown cancels `setupTask`
    /// synchronously on the main actor, so a resumed setup must not assign
    /// resources (leaked monitor/bridge) or deliver stale results.
    func performSetup(engine: JSEngineProtocol) async {
        do {
            let domain = configuration.page.host.toDotDomain()

            subscribeProgress(domain: domain)

            let contentURL = try await dotNsResolver.resolveToLocalURL(dotNsName: domain)
            let schemeHandler = makeSchemeHandler(
                domain: domain,
                contentURL: contentURL
            )

            guard let productURL = schemeHandler.getProductUrl() else { return }

            logger.debug("SPA: '\(domain)' content resolved to \(contentURL.path)")

            schemeHandlerProxy.setHandler(schemeHandler)

            let scripts = try scriptsFactory.makeScripts()
            try await engine.initialize(with: scripts)

            guard !Task.isCancelled else { return }

            let monitor = JSEngineMonitor(engine: engine)
            monitor.start()
            engineMonitor = monitor

            logger.debug("SPA: Engine initialized")

            let bridge = ContainerBridge(engine: engine, logger: logger)
            await bridge.registerHostApiHandlers(
                nativeApi: nativeApi,
                onRenderWidget: { _, _ in }
            )
            await bridge.install()

            guard !Task.isCancelled else {
                await bridge.dispose()
                return
            }

            containerBridge = bridge
            logger.debug("SPA: ContainerBridge installed")

            let initialURL = configuration.page.applied(to: productURL)
            presenter?.didRequestNavigation(to: initialURL)
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("SPA: Setup failed: \(error)")
            presenter?.didFail(error: error)
        }
    }

    func makeSchemeHandler(
        domain: String,
        contentURL: URL
    ) -> ProductScriptSchemeHandler {
        let fileProvider = DotNsFileProvider(contentURL: contentURL)

        return ProductScriptSchemeHandler(
            productId: domain,
            entryRelativePath: ProductBundle.indexHTML,
            productFileProvider: fileProvider
        )
    }
}
