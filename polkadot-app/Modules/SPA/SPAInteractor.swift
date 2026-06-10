import Foundation
import Operation_iOS
import Products

final class SPAInteractor {
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
        dispose()
    }
}

extension SPAInteractor: SPAInteractorInputProtocol {
    func setup(engine: JSEngineProtocol) {
        jsEngine = engine
        setupTask = Task { [weak self] in
            await self?.performSetup(engine: engine)
        }
    }

    func retry() {
        guard let engine = jsEngine else { return }

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
                    await self?.presenter?.didPrepareChat(chatId: chatId)
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

private extension SPAInteractor {
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

    func dispose() {
        setupTask?.cancel()
        setupTask = nil

        openChatTask?.cancel()
        openChatTask = nil

        engineMonitor?.stop()
        engineMonitor = nil
        let bridge = containerBridge
        containerBridge = nil

        let engine = jsEngine
        jsEngine = nil

        Task {
            await bridge?.dispose()
            await engine?.destroy()
        }
    }

    func performSetup(engine: JSEngineProtocol) async {
        do {
            let domain = configuration.page.host.toDotDomain()

            let contentDirectory = try await dotNsResolver.resolveToLocalURL(dotNsName: domain)
            let schemeHandler = makeSchemeHandler(
                domain: domain,
                contentDirectory: contentDirectory
            )

            guard let productURL = schemeHandler.getProductUrl() else { return }

            logger.debug("SPA: '\(domain)' resolved to \(contentDirectory.path)")

            await schemeHandlerProxy.setHandler(schemeHandler)

            let scripts = try scriptsFactory.makeScripts()
            try await engine.initialize(with: scripts)

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

            containerBridge = bridge
            logger.debug("SPA: ContainerBridge installed")

            let initialURL = configuration.page.applied(to: productURL)
            await presenter?.didRequestNavigation(to: initialURL)
        } catch {
            logger.error("SPA: Setup failed: \(error)")
            await presenter?.didFail(error: error)
        }
    }

    func makeSchemeHandler(
        domain: String,
        contentDirectory: URL
    ) -> ProductScriptSchemeHandler {
        let fileProvider = DotNsFileProvider(contentDirectory: contentDirectory)

        return ProductScriptSchemeHandler(
            productId: domain,
            entryRelativePath: ProductBundle.indexHTML,
            productFileProvider: fileProvider
        )
    }
}
