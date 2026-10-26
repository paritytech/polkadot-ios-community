import Foundation
import FoundationExt
import StatementStore
import SubstrateSdk
import SubstrateSdkExt

struct DeviceTransferDiscoveryConfiguration {
    let connection: StatementStoreConnecting
    let signer: StatementStoreSigning
}

protocol DeviceTransferRequestPublishing: Sendable {
    func publishRequest(configuration: DeviceTransferDiscoveryConfiguration) async throws -> DeviceTransferRequest
    func cancel(requestId: String, configuration: DeviceTransferDiscoveryConfiguration) async throws
}

/// The new phone's side of discovery: one statement on `request_topic`, replaced by a newer request or a cancel.
actor DeviceTransferRequestPublisher {
    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let deviceInfo: DeviceInfo
    private let dateProvider: any DateProviding

    private var lastExpiry: UInt64 = 0

    init(
        keyScheduleFactory: DeviceTransferKeyScheduleMaking,
        deviceInfo: DeviceInfo,
        dateProvider: any DateProviding = NowDateProvider()
    ) {
        self.keyScheduleFactory = keyScheduleFactory
        self.deviceInfo = deviceInfo
        self.dateProvider = dateProvider
    }
}

extension DeviceTransferRequestPublisher: DeviceTransferRequestPublishing {
    func publishRequest(configuration: DeviceTransferDiscoveryConfiguration) async throws -> DeviceTransferRequest {
        let now = await dateProvider.read()
        let request = DeviceTransferRequest(
            requestId: UUID().uuidString.lowercased(),
            deviceModel: deviceInfo.model,
            operatingSystem: deviceInfo.operatingSystem,
            createdAt: UInt64(now.timeIntervalSince1970.milliseconds)
        )

        try await publish(.request(request), at: now, configuration: configuration)
        return request
    }

    func cancel(requestId: String, configuration: DeviceTransferDiscoveryConfiguration) async throws {
        try await publish(.cancel(requestId: requestId), at: dateProvider.read(), configuration: configuration)
    }
}

private extension DeviceTransferRequestPublisher {
    func publish(
        _ message: DeviceTransferMessage,
        at date: Date,
        configuration: DeviceTransferDiscoveryConfiguration
    ) async throws {
        let schedule = try keyScheduleFactory.makeKeySchedule()
        let sealed = try DeviceTransferMessageCipher(requestKey: schedule.requestKey).seal(message)

        let builder = try StatementSubmitParametersBuilder(signer: configuration.signer, logger: nil)
            .addTopic1(schedule.requestTopic)
            .addChannel(schedule.requestTopic)
            .addExpiry(nextExpiry(at: date))
            .addScaleEncodedPayload(sealed.scaleEncoded())

        try await configuration.connection.submitStatement(with: builder)
    }

    /// A cancel sent in the same second as its request still has to outrank it on the channel.
    func nextExpiry(at date: Date) -> UInt64 {
        let expiresAt = UInt64(date.timeIntervalSince1970 + DeviceTransferConstants.statementLifetimeInSeconds)
        lastExpiry = max(expiresAt << 32, lastExpiry + 1)
        return lastExpiry
    }
}
