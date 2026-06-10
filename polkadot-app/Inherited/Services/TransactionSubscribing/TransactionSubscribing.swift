import Foundation
import SubstrateSdk

protocol TransactionSubscribing {
    func process(blockHash: Data)
}

protocol TransactionSubscriptionFactoryProtocol {
    func createTransactionSubscription(
        for accountId: AccountId,
        chain: ChainModel
    ) throws -> TransactionSubscribing
}
