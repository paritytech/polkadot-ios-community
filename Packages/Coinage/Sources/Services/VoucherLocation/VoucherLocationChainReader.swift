import Foundation
import AsyncExtensions
import SDKLogger
import SubstrateSdk
import SubstrateStorageSubscription
import StructuredConcurrency
import Individuality

/// The chain reads the location pipeline makes, behind one seam so the pipeline can be driven from a
/// test without runtime metadata.
protocol VoucherLocationChainReading: Sendable {
    func ringKeysPageSize() async throws -> Int
    func subscribe(_ requests: [BatchStorageSubscriptionRequest]) -> AnyAsyncSequence<MemberStatusResult>
}

final class VoucherLocationChainReader: VoucherLocationChainReading, @unchecked Sendable {
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let logger: SDKLoggerProtocol

    init(connection: JSONRPCEngine, runtimeService: RuntimeCodingServiceProtocol, logger: SDKLoggerProtocol) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.logger = logger
    }

    func ringKeysPageSize() async throws -> Int {
        try await runtimeService.fetchRingKeysPageSize()
    }

    func subscribe(_ requests: [BatchStorageSubscriptionRequest]) -> AnyAsyncSequence<MemberStatusResult> {
        CallbackBatchStorageSubscription.asyncStream(
            requests: requests,
            connection: connection,
            runtimeService: runtimeService,
            logger: logger
        )
    }
}
