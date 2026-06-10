import Foundation
import Operation_iOS

final class SSODisconnectHandler: SSORequestHandling {
    private let hostRepository: AnyDataProviderRepository<PolkadotSignInHost>
    private let localDeviceRepository: AnyDataProviderRepository<Chat.LocalDevice>
    private let deviceMessageBroadcaster: DeviceMessageBroadcasting
    private let logger: LoggerProtocol

    init(
        hostRepositoryFactory: PolkadotSignInHostRepositoryMaking = PolkadotSignInHostRepositoryFactory(),
        localDeviceRepositoryFactory: LocalDeviceRepositoryMaking = LocalDeviceRepositoryFactory(),
        deviceMessageBroadcaster: DeviceMessageBroadcasting = MultideviceComponentFactory
            .makeDeviceMessageBroadcaster(
                messageExchangeModeProvider: ChatMessageExchangeModeProvider()
            ),
        logger: LoggerProtocol = Logger.shared
    ) {
        hostRepository = hostRepositoryFactory.createRepository(forFilter: nil)
        localDeviceRepository = localDeviceRepositoryFactory.createRepository(forFilter: nil)
        self.deviceMessageBroadcaster = deviceMessageBroadcaster
        self.logger = logger
    }

    func canHandle(_ content: PolkadotHostRemoteMessage.LatestContent) -> Bool {
        if case .disconnected = content { return true }
        return false
    }

    func handle(
        message _: PolkadotHostRemoteMessage,
        from host: PolkadotSignInHost
    ) async {
        logger.info("Got disconnected message from host \(host.name)")

        let statementAccountId = host.accountId
        let deviceIdentifier = statementAccountId.toHex()

        do {
            let removeHostOperation = hostRepository.saveOperation({ [] }, { [host.identifier] })
            try await removeHostOperation.asyncExecute()
            logger.debug("Removed host \(host.name)")
        } catch {
            logger.error("Failed to remove host \(host.name): \(error)")
        }

        do {
            let removeDeviceOperation = localDeviceRepository.saveOperation({ [] }, { [deviceIdentifier] })
            try await removeDeviceOperation.asyncExecute()
            logger.debug("Removed local device for host \(host.name)")
        } catch {
            logger.error("Failed to remove local device for host \(host.name): \(error)")
        }

        do {
            try await deviceMessageBroadcaster.broadcastDeviceRemoved(
                statementAccountId: statementAccountId
            )
            logger.debug("Broadcast deviceRemoved for host \(host.name)")
        } catch {
            logger.error("Failed to broadcast deviceRemoved for host \(host.name): \(error)")
        }
    }
}
