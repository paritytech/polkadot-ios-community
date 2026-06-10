import Foundation
import SubstrateSdk
import Individuality
import Combine

enum ChatIdentifierServiceError: Error {
    case identifierNotFound
}

protocol ChatIdentifierServiceProtocol {
    /// Creates a one-time query to **Game.CommunicationIdentifiers** storage
    func fetch(for accountId: AccountId) async throws -> Data?
}

final class ChatIdentifierService: BaseSubscriptionService {}

extension ChatIdentifierService: ChatIdentifierServiceProtocol {
    func fetch(for accountId: AccountId) async throws -> Data? {
        let path = GamePallet.Storage.communicationIdentifier(accountId)

        let publisher: AnyPublisher<BytesCodable?, Error> = queryStorage(
            at: path,
            params: [BytesCodable(wrappedValue: accountId)]
        )

        do {
            for try await value in publisher.values {
                return value?.wrappedValue
            }
            // Stream finished without value
            return nil
        } catch SubscriptionServiceError.noData {
            return nil
        } catch {
            throw error
        }
    }
}
