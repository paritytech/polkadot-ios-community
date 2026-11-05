import Foundation

/// Hands the active status to this phone once the run has applied the data and imported the device key.
/// The push token needs no step here: chat starts after finalize, and transferred contacts have no last own token,
/// so `ChatPushService` sends this phone's token to each of them.
final class DeviceTransferFinalizer: @unchecked Sendable {
    private let installationPublisher: ActiveInstallationPublishing
    private let processedStore: DeviceTransferProcessedStoring
    private let checkpointStore: DeviceTransferCheckpointStoring
    private let publishRetry: ActiveInstallationPublishRetry
    private let logger: LoggerProtocol

    init(
        installationPublisher: ActiveInstallationPublishing,
        processedStore: DeviceTransferProcessedStoring,
        checkpointStore: DeviceTransferCheckpointStoring,
        publishRetry: ActiveInstallationPublishRetry = ActiveInstallationPublishRetry(),
        logger: LoggerProtocol
    ) {
        self.installationPublisher = installationPublisher
        self.processedStore = processedStore
        self.checkpointStore = checkpointStore
        self.publishRetry = publishRetry
        self.logger = logger
    }
}

extension DeviceTransferFinalizer: DeviceTransferFinalizing {
    /// A failed publish keeps the checkpoint, so a new transfer resumes where this one ended.
    func finalize(after request: DeviceTransferRequest) async throws {
        try await installationPublisher.publishSelf(retry: publishRetry)
        await markOwnRequestProcessed(request)
        checkpointStore.clear()

        logger.info("Device transfer finalized for request \(request.requestId)")
    }
}

private extension DeviceTransferFinalizer {
    /// Once active, this phone's listener follows the request topic and would otherwise offer its own request.
    func markOwnRequestProcessed(_ request: DeviceTransferRequest) async {
        do {
            try await processedStore.markProcessed(requestId: request.requestId, outcome: .accepted)
        } catch {
            logger.error("Failed to mark own device transfer request processed: \(error)")
        }
    }
}
