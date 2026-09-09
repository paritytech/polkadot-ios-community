import AsyncExtensions
import Foundation
import KeyDerivation
import SubstrateSdk
@testable import Coinage

/// Inert `ClaimCoinsServicing` — never drives anything; `accept` tests don't reach it.
final class StubClaimCoinsService: ClaimCoinsServicing, @unchecked Sendable {
    func claim(
        coinKeys _: [Data],
        groupId _: CoinageTxGroupId,
        retryUntil _: Date,
        context _: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection> {
        AsyncStream<CoinageTransferDetection> { $0.finish() }.eraseToAnyAsyncSequence()
    }
}

/// Inert `ClaimAssetServicing`.
final class StubClaimAssetService: ClaimAssetServicing, @unchecked Sendable {
    func claim(
        wallet _: any WalletManaging,
        amount _: Balance,
        groupId _: CoinageTxGroupId,
        retryUntil _: Date,
        instanceId _: CoinageInstanceId,
        context _: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection> {
        AsyncStream<CoinageTransferDetection> { $0.finish() }.eraseToAnyAsyncSequence()
    }
}

/// Inert `CoinageTxServicing` — group observation returns empty; `accept` never touches it.
final class StubCoinageTxServicing: CoinageTxServicing, @unchecked Sendable {
    func submitTransactions(_: [CoinageTxRequest], groupId _: CoinageTxGroupId?) async throws -> [CoinageTxId] { [] }

    func subscribeTransactionStatus(_: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus> {
        AsyncStream<CoinageTxStatus> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func getOperationGroupStatuses(_: CoinageTxGroupId) async throws -> [CoinageTxEntry] { [] }

    func subscribeOperationGroupStatuses(_: CoinageTxGroupId) -> AnyAsyncSequence<[CoinageTxEntry]> {
        AsyncStream<[CoinageTxEntry]> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func startRecoveryPass() {}
    func start() {}
    func stop() {}

    func preCommitHandoff(_: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        fatalError("preCommitHandoff is not exercised by incoming-payment tests")
    }

    func releaseUncommittedHandoffs() async throws {}
}

/// Denomination provider that reports the context as unavailable — `accept` never calls it.
final class StubDenominationContextProvider: DenominationContextProviding, @unchecked Sendable {
    struct Unavailable: Error {}

    func denominationContext() async throws -> DenominationBreakdownContext {
        throw Unavailable()
    }
}
