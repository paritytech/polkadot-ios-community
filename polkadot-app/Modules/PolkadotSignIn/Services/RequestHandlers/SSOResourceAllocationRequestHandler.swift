import Foundation
import Products
import Individuality

final class SSOResourceAllocationRequestHandler: SSORequestHandling {
    private let accountManager: ProductsAccountManaging
    private let messageSender: PolkadotHostMessageSending
    private let logger: LoggerProtocol

    init(
        accountManager: ProductsAccountManaging,
        messageSender: PolkadotHostMessageSending,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountManager = accountManager
        self.messageSender = messageSender
        self.logger = logger
    }

    func canHandle(_ content: PolkadotHostRemoteMessage.LatestContent) -> Bool {
        if case .resourceAllocationRequest = content { return true }
        return false
    }

    func handle(
        message: PolkadotHostRemoteMessage,
        from host: PolkadotSignInHost
    ) async {
        guard case let .resourceAllocationRequest(request) = message.latestContent() else {
            return
        }

        logger.info("Resource allocation request received from \(host.name)")

        let outcomes: [AllocationOutcome]

        do {
            outcomes = try await accountManager.requestResourceAllocation(
                for: request.callingProduct,
                resources: request.resources,
                policy: request.onExisting
            )
        } catch {
            logger.error("Failed to allocate resources: \(error)")
            outcomes = request.resources.map { _ in .notAvailable }
        }

        let responseMessage = PolkadotHostRemoteMessage(
            messageId: UUID().uuidString,
            versionedContent: .v1(.resourceAllocationResponse(
                requestMessageId: message.messageId,
                result: .success(outcomes)
            ))
        )

        do {
            try await messageSender.postMessage(responseMessage, to: host)
        } catch {
            logger.error("Failed to send resource allocation response: \(error)")
        }
    }
}
