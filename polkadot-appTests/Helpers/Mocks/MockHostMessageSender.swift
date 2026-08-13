import Foundation
import MessageExchangeKit

@testable import polkadot_app

// MARK: - Mock Host Message Sender

final class MockHostMessageSender: PolkadotHostMessageSending, @unchecked Sendable {
    private(set) var postedMessages: [PolkadotHostRemoteMessage] = []

    func setExchangeService(_: AnyMessageExchangeService<OpaquePolkadotHostRemoteMessage>) async {}

    func postMessage(_ message: PolkadotHostRemoteMessage, to _: PolkadotSignInHost) async throws {
        postedMessages.append(message)
    }

    func handleDidPostMessages(_: [PolkadotHostRemoteMessage], withError _: Error?) async {}

    func cancelPendingMessages(excluding _: Set<String>) async {}
}
