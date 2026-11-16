import Coinage
import Foundation
import IssueMonitoring

struct DeviceTransferFinalizerSettings {
    var publishRetry = ActiveInstallationPublishRetry()
    var publishFailureDiagnostic: IssueDiagnostic = NoopIssueDiagnostic()
}

/// Hands the active status to this phone once the run has applied the data and imported the device key.
/// The push token needs no step here: chat starts after finalize, and transferred contacts have no last own token,
/// so `ChatPushService` sends this phone's token to each of them.
final class DeviceTransferFinalizer: @unchecked Sendable {
    private let installationPublisher: ActiveInstallationPublishing
    private let processedStore: DeviceTransferProcessedStoring
    private let checkpointStore: DeviceTransferCheckpointStoring
    private let installationRepository: any CoinageInstallationRepositoryProtocol
    private let settings: DeviceTransferFinalizerSettings
    private let logger: LoggerProtocol

    init(
        installationPublisher: ActiveInstallationPublishing,
        processedStore: DeviceTransferProcessedStoring,
        checkpointStore: DeviceTransferCheckpointStoring,
        installationRepository: any CoinageInstallationRepositoryProtocol,
        settings: DeviceTransferFinalizerSettings = DeviceTransferFinalizerSettings(),
        logger: LoggerProtocol
    ) {
        self.installationPublisher = installationPublisher
        self.processedStore = processedStore
        self.checkpointStore = checkpointStore
        self.installationRepository = installationRepository
        self.settings = settings
        self.logger = logger
    }
}

extension DeviceTransferFinalizer: DeviceTransferFinalizing {
    /// A failed publish keeps the checkpoint, so a new transfer resumes where this one ended.
    func finalize(after request: DeviceTransferRequest, from senderInstallationId: Data) async throws {
        do {
            try await installationPublisher.publishSelf(retry: settings.publishRetry)
        } catch {
            settings.publishFailureDiagnostic.recordFailure(
                for: "publish",
                error: error,
                counters: ["attempts": settings.publishRetry.attempts]
            )
            throw error
        }

        await markOwnRequestProcessed(request)
        await rescanCoinage(of: senderInstallationId)
        checkpointStore.clear()

        logger.info("Device transfer finalized for request \(request.requestId)")
    }
}

private extension DeviceTransferFinalizer {
    /// The old phone's coinage is read again from index 0 once this phone is active: its last claims may have
    /// finalized after an earlier scan closed the cursor. A failure only leaves it to the contract listing.
    func rescanCoinage(of senderInstallationId: Data) async {
        do {
            try await installationRepository.addPrevious([CoinageInstallationId(value: senderInstallationId)])
            try await installationRepository.resetScans()
        } catch {
            logger.error("Failed to schedule the coinage rescan after the transfer: \(error)")
        }
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
