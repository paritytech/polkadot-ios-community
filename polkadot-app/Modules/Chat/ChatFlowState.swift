import Foundation
import Coinage

final class ChatFlowState {
    let extensionsRegistry: ChatExtensionsRegistering
    let callCoordinator: CallCoordinating
    let outboxService: ChatOutboxServicing
    let attachmentUploadStateProvider: AttachmentLoadProgressProvidable
    let attachmentDownloadStateProvider: AttachmentLoadProgressProvidable
    let audioSessionManager: AudioSessionManaging
    weak var foregroundVisibilityReporter: PushForegroundVisibilityReporting?

    let notificationsCleaner: any PushNotificationsCleaning
    let coinageService: CoinageServicing

    init(
        extensionsRegistry: ChatExtensionsRegistering,
        callCoordinator: CallCoordinating,
        outboxService: ChatOutboxServicing,
        attachmentUploadStateProvider: AttachmentLoadProgressProvidable,
        attachmentDownloadStateProvider: AttachmentLoadProgressProvidable,
        foregroundVisibilityReporter: PushForegroundVisibilityReporting?,
        audioSessionManager: AudioSessionManaging,
        notificationsCleaner: any PushNotificationsCleaning,
        coinageService: CoinageServicing
    ) {
        self.extensionsRegistry = extensionsRegistry
        self.callCoordinator = callCoordinator
        self.outboxService = outboxService
        self.attachmentUploadStateProvider = attachmentUploadStateProvider
        self.attachmentDownloadStateProvider = attachmentDownloadStateProvider
        self.foregroundVisibilityReporter = foregroundVisibilityReporter
        self.audioSessionManager = audioSessionManager
        self.notificationsCleaner = notificationsCleaner
        self.coinageService = coinageService
    }
}
