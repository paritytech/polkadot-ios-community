import Foundation
import Operation_iOS
import Products

/// Rust-runtime SPA interactor: creates the runtime via the factory, attaches
/// the presentation view, and forwards the start URL to the presenter. All
/// setup logic lives in the runtime itself.
@MainActor
final class SPARustRuntimeInteractor {
    weak var presenter: SPAInteractorOutputProtocol?

    private let runtimeFactory: SPARuntimeFactoryProtocol
    private let dotNsResolver: DotNsResolverProtocol
    private let configuration: SPAConfiguration
    private let logger: LoggerProtocol
    private let productRepository: AnyDataProviderRepository<Product>
    private let chatProviderFactory: ChatContactDataProviderMaking

    private var runtime: SPARuntimeProtocol?
    private var jsEngine: JSEngineProtocol?

    private var setupTask: Task<Void, Never>?
    private var openChatTask: Task<Void, Never>?

    init(
        runtimeFactory: SPARuntimeFactoryProtocol,
        dotNsResolver: DotNsResolverProtocol,
        configuration: SPAConfiguration,
        logger: LoggerProtocol,
        productRepository: AnyDataProviderRepository<Product>,
        chatProviderFactory: ChatContactDataProviderMaking
    ) {
        self.runtimeFactory = runtimeFactory
        self.dotNsResolver = dotNsResolver
        self.configuration = configuration
        self.logger = logger
        self.productRepository = productRepository
        self.chatProviderFactory = chatProviderFactory
    }

    deinit {
        setupTask?.cancel()
        openChatTask?.cancel()
        // Runtime ownership contract: the holder disposes before release.
        Task { [runtime] in await runtime?.dispose() }
    }
}

extension SPARustRuntimeInteractor: SPAInteractorInputProtocol {
    func setup(engine: JSEngineProtocol) {
        jsEngine = engine

        startRuntime(engine: engine)
    }

    func retry() {
        guard let engine = jsEngine else { return }

        let previousRuntime = runtime
        runtime = nil
        Task { await previousRuntime?.dispose() }

        startRuntime(engine: engine)
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
                self?.logger.error("SPA(rust): Failed to open chat: \(error)")
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

private extension SPARustRuntimeInteractor {
    func startRuntime(engine: JSEngineProtocol) {
        setupTask?.cancel()

        do {
            let newRuntime = try runtimeFactory.createRuntime(
                for: configuration.page.host.toDotDomain()
            )
            runtime = newRuntime

            setupTask = Task { [weak self] in
                do {
                    let url = try await newRuntime.start(with: engine)
                    self?.presenter?.didRequestNavigation(to: url)
                } catch is CancellationError {
                    // Superseded by retry/teardown — the replacement reports.
                } catch {
                    self?.logger.error("SPA(rust): Setup failed: \(error)")
                    self?.presenter?.didFail(error: error)
                }
            }
        } catch {
            logger.error("SPA(rust): Runtime creation failed: \(error)")
            presenter?.didFail(error: error)
        }
    }

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
}
