import Foundation

struct ChatSignalStateObserver: @unchecked Sendable {
    let messageId: Chat.MessageId
    let providerFactory: ChatMessageDataProviderMaking
    let workQueue: DispatchQueue
}

extension ChatSignalStateObserver: PeerConnectionSignalStateObserving {
    func wait(for state: PeerConnectionSignalState) async throws {
        try await ChatMessageStatusAwaiter.waitUntilOutgoingStatusReached(
            messageId: messageId,
            target: state.outgoingTarget,
            providerFactory: providerFactory,
            workQueue: workQueue
        )
    }
}

private extension PeerConnectionSignalState {
    var outgoingTarget: Chat.LocalMessage.Status.OutgoingStatus {
        switch self {
        case .sent: .sent
        case .delivered: .delivered
        }
    }
}
