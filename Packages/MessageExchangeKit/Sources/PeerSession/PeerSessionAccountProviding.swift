import Foundation
import StatementStore

/// The account id a session uses for its own side: in the SessionId, the statement coder and the own-topic
/// subscriptions. Statements are signed separately, through `PeerSessionSignerResolving`.
public protocol PeerSessionAccountProviding {
    func ownAccountId(for own: MessageExchange.Own) throws -> MessageExchange.AccountId
}

public final class SignerSessionAccountProvider {
    private let signerManager: StatementStoreSignerManaging

    public init(signerManager: StatementStoreSignerManaging) {
        self.signerManager = signerManager
    }
}

extension SignerSessionAccountProvider: PeerSessionAccountProviding {
    public func ownAccountId(for own: MessageExchange.Own) throws -> MessageExchange.AccountId {
        try signerManager.makeSigner(for: own.signKeyId).accountId
    }
}

/// Uses one account id for every session, e.g. a label standing in for an account that never signs.
public struct FixedSessionAccountProvider: PeerSessionAccountProviding {
    public let accountId: MessageExchange.AccountId

    public init(accountId: MessageExchange.AccountId) {
        self.accountId = accountId
    }

    public func ownAccountId(for _: MessageExchange.Own) throws -> MessageExchange.AccountId {
        accountId
    }
}
