import AsyncExtensions
import Foundation
import KeyDerivation
import os
import SubstrateSdk
@testable import Coinage

/// In-memory `IncomingPaymentSecretStoring` for tests. Records removals for wipe-on-settle assertions.
final class InMemoryIncomingPaymentSecretStore: IncomingPaymentSecretStoring, @unchecked Sendable {
    struct Failure: Error {}

    private struct State {
        var descriptors: [CoinageTxGroupId: IncomingPaymentSourceDescriptor] = [:]
        var removed: [CoinageTxGroupId] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    var saveError: Error?
    var fetchError: Error?

    init(seed: [CoinageTxGroupId: IncomingPaymentSourceDescriptor] = [:]) {
        state.withLock { $0.descriptors = seed }
    }

    func save(groupId: CoinageTxGroupId, descriptor: IncomingPaymentSourceDescriptor) throws {
        if let saveError { throw saveError }
        state.withLock { $0.descriptors[groupId] = descriptor }
    }

    func fetch(groupId: CoinageTxGroupId) throws -> IncomingPaymentSourceDescriptor? {
        if let fetchError { throw fetchError }
        return state.withLock { $0.descriptors[groupId] }
    }

    func remove(groupId: CoinageTxGroupId) {
        state.withLock { state in
            state.descriptors[groupId] = nil
            state.removed.append(groupId)
        }
    }

    func removedGroupIds() -> [CoinageTxGroupId] { state.withLock { $0.removed } }
    func hasDescriptor(for groupId: CoinageTxGroupId) -> Bool { state.withLock { $0.descriptors[groupId] != nil } }
}

/// Resolver stub — succeeds (returning inert claim material) or throws to exercise `InvalidSource`.
final class StubSourceResolver: IncomingPaymentSourceResolving, @unchecked Sendable {
    struct Invalid: Error {}

    let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func resolve(descriptor: IncomingPaymentSourceDescriptor) async throws -> ResolvedIncomingSource {
        if shouldFail { throw Invalid() }
        switch descriptor {
        case let .coins(secretKeys): return .coins(secretKeys: secretKeys)
        // accept tests don't run the claim; a wallet is not needed here.
        case .privateKey,
             .productAccount: return .coins(secretKeys: [])
        }
    }
}

/// Acknowledger stub — records what it was asked to surface.
final class StubAcknowledger: IncomingPaymentAcknowledging, @unchecked Sendable {
    struct Call: Equatable {
        let productId: String
        let paymentId: IncomingPaymentId
        let requestedAmount: Balance
        let outcome: IncomingPaymentTerminalOutcome
    }

    private let lock = OSAllocatedUnfairLock(initialState: [Call]())

    func acknowledge(
        productId: String,
        paymentId: IncomingPaymentId,
        requestedAmount: Balance,
        outcome: IncomingPaymentTerminalOutcome
    ) async {
        lock.withLock {
            $0.append(Call(
                productId: productId,
                paymentId: paymentId,
                requestedAmount: requestedAmount,
                outcome: outcome
            ))
        }
    }

    func calls() -> [Call] { lock.withLock { $0 } }
}

/// `ClaimCoinsServicing` that replays a fixed detection sequence, then finishes. Records the
/// `retryUntil` it was handed so tests can pin the retry window.
final class StubClaimCoinsService: ClaimCoinsServicing, @unchecked Sendable {
    private let detections: [CoinageTransferDetection]
    private let capturedRetryUntil = OSAllocatedUnfairLock<Date?>(initialState: nil)

    init(detections: [CoinageTransferDetection] = []) {
        self.detections = detections
    }

    func claim(
        coinKeys _: [Data],
        groupId _: CoinageTxGroupId,
        retryUntil: Date,
        context _: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection> {
        capturedRetryUntil.withLock { $0 = retryUntil }
        let detections = detections
        return AsyncStream<CoinageTransferDetection> { continuation in
            for detection in detections {
                continuation.yield(detection)
            }
            continuation.finish()
        }.eraseToAnyAsyncSequence()
    }

    func retryUntil() -> Date? { capturedRetryUntil.withLock { $0 } }
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

/// `CoinageGroupVerdictResolving` that answers with a fixed verdict, or throws. Records the groups it
/// was asked about so a test can tell the durability fallback ran.
final class StubGroupVerdictResolver: CoinageGroupVerdictResolving, @unchecked Sendable {
    struct Unobservable: Error {}

    private let result: Result<CoinageTransferDetection, Error>
    private let asked = OSAllocatedUnfairLock(initialState: [CoinageTxGroupId]())

    init(verdict: CoinageTransferDetection) {
        result = .success(verdict)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func settledVerdict(
        groupId: CoinageTxGroupId,
        amount _: Balance,
        context _: DenominationBreakdownContext
    ) async throws -> CoinageTransferDetection {
        asked.withLock { $0.append(groupId) }
        return try result.get()
    }

    func askedGroupIds() -> [CoinageTxGroupId] { asked.withLock { $0 } }
}
