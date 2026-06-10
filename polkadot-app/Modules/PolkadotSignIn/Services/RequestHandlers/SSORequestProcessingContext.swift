import Foundation

actor SSORequestProcessingContext {
    struct PendingRequest {
        let message: PolkadotHostRemoteMessage
        let host: PolkadotSignInHost
    }

    private var pendingRequests: [PendingRequest] = []
    private var activeTask: Task<Void, Never>?
    private let handlers: [SSORequestHandling]
    private let logger: LoggerProtocol

    init(
        handlers: [SSORequestHandling],
        logger: LoggerProtocol = Logger.shared
    ) {
        self.handlers = handlers
        self.logger = logger
    }

    func enqueue(message: PolkadotHostRemoteMessage, from host: PolkadotSignInHost) {
        let pending = PendingRequest(message: message, host: host)

        if activeTask == nil {
            logger.info("Processing task right away")
            startProcessing(pending)
        } else {
            pendingRequests.append(pending)
            logger.info("Queued request \(message.messageId), queue size: \(pendingRequests.count)")
        }
    }

    func cancelAll() {
        activeTask?.cancel()
        activeTask = nil
        pendingRequests.removeAll()
    }
}

private extension SSORequestProcessingContext {
    func startProcessing(_ request: PendingRequest) {
        activeTask = Task { [weak self] in
            await self?.process(request)
            await self?.processNext()
        }
    }

    func process(_ request: PendingRequest) async {
        guard let content = request.message.latestContent() else {
            logger.error("Failed to get content for message \(request.message.messageId)")
            return
        }

        for handler in handlers {
            if handler.canHandle(content) {
                logger.info("Processing \(request.message.messageId) with \(type(of: handler))")
                await handler.handle(
                    message: request.message,
                    from: request.host
                )
                return
            }
        }

        logger.warning("No handler for message \(request.message.messageId)")
    }

    func processNext() {
        activeTask = nil

        guard !pendingRequests.isEmpty else {
            return
        }

        let next = pendingRequests.removeFirst()
        logger.debug("Dequeuing \(next.message.messageId), remaining: \(pendingRequests.count)")
        startProcessing(next)
    }
}
