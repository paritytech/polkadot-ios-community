import Foundation
import PolkadotUI
import Products

extension ChatPresenter {
    @MainActor
    func didReclaim(messageId: Chat.MessageId) {
        pendingReclaimMessageIds.remove(messageId)
    }

    @MainActor
    func didFailReclaim(messageId: Chat.MessageId, error: Error) {
        pendingReclaimMessageIds.remove(messageId)

        if !wireframe.present(error: error, from: view) {
            wireframe.present(
                message: String(localized: .Common.errorMessage),
                title: nil,
                closeAction: String(localized: .Common.close),
                from: view
            )
        }
    }

    func handleReclaimTransfer(for messageId: String) {
        guard
            !pendingReclaimMessageIds.contains(messageId),
            let message = listModel?.getMessage(by: messageId),
            case let .coinageSend(content) = message.content,
            content.isReclaimable
        else {
            return
        }

        pendingReclaimMessageIds.insert(messageId)
        interactor.reclaimTransfer(messageId: messageId, coinKeys: content.coinKeys)
    }
}
