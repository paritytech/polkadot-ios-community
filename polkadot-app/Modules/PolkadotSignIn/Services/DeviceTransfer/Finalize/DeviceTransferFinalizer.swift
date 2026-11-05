import Foundation
import StructuredConcurrency

struct DeviceTransferFinalizerSettings {
    var publishAttempts = 10
    var publishRetryDelay: Duration = .seconds(1)
}

/// Hands the active status to this phone once the run has applied the data and imported the device key.
/// The push token needs no step here: chat starts after finalize, and transferred contacts have no last own token,
/// so `ChatPushService` sends this phone's token to each of them.
final class DeviceTransferFinalizer: @unchecked Sendable {
    private let installationPublisher: ActiveInstallationPublishing
    private let processedStore: DeviceTransferProcessedStoring
    private let checkpointStore: DeviceTransferCheckpointStoring
    private let settings: DeviceTransferFinalizerSettings
    private let logger: LoggerProtocol

    init(
        installationPublisher: ActiveInstallationPublishing,
        processedStore: DeviceTransferProcessedStoring,
        checkpointStore: DeviceTransferCheckpointStoring,
        settings: DeviceTransferFinalizerSettings = DeviceTransferFinalizerSettings(),
        logger: LoggerProtocol
    ) {
        self.installationPublisher = installationPublisher
        self.processedStore = processedStore
        self.checkpointStore = checkpointStore
        self.settings = settings
        self.logger = logger
    }
}

extension DeviceTransferFinalizer: DeviceTransferFinalizing {
    /// A failed publish keeps the checkpoint, so a new transfer resumes where this one ended.
    func finalize(after request: DeviceTransferRequest) async throws {
        try await publishActiveRecord()
        await markOwnRequestProcessed(request)
        checkpointStore.clear()

        logger.info("Device transfer finalized for request \(request.requestId)")
    }
}

private extension DeviceTransferFinalizer {
    func publishActiveRecord() async throws {
        let publisher = installationPublisher

        try await withRetry(
            maxAttempts: settings.publishAttempts,
            initialDelay: settings.publishRetryDelay,
            shouldRetry: { !($0 is ActiveInstallationServiceError) },
            operation: { try await publisher.publishSelf() }
        )
    }

    /// Once active, this phone's listener follows the request topic and would otherwise offer its own request.
    func markOwnRequestProcessed(_ request: DeviceTransferRequest) async {
        do {
            try await processedStore.markProcessed(requestId: request.requestId, outcome: .accepted)
        } catch {
            logger.error("Failed to mark own device transfer request processed: \(error)")
        }
    }
}
