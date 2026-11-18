import ChainStore
import Foundation
import SDKLogger
import SubstrateSdk
import SubstrateStorageQuery

public protocol NotificationParametersProviding: Sendable {
    func currentPeriod() async throws -> UInt32
    func maxStatementSize() async throws -> Int
}

public enum NotificationParametersError: Error {
    case zeroPeriodDuration
}

public final class NotificationParametersProvider: @unchecked Sendable {
    private let chainId: ChainId
    private let chainRegistry: ChainResourceProtocol
    private let chainTimeProvider: ChainTimeProviding
    private let statementStorageParameters: StatementStorageParametersProviding
    private let logger: SDKLoggerProtocol

    public init(
        chainId: ChainId,
        chainRegistry: ChainResourceProtocol,
        chainTimeProvider: ChainTimeProviding,
        statementStorageParameters: StatementStorageParametersProviding,
        logger: SDKLoggerProtocol
    ) {
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.chainTimeProvider = chainTimeProvider
        self.statementStorageParameters = statementStorageParameters
        self.logger = logger
    }
}

extension NotificationParametersProvider: NotificationParametersProviding {
    public func currentPeriod() async throws -> UInt32 {
        let duration: StringCodable<UInt32> = try await constant(.notificationPeriodDuration)

        return try await Self.period(atSeconds: chainTimeProvider.nowSeconds(), duration: duration.wrappedValue)
    }

    public func maxStatementSize() async throws -> Int {
        if let allowance = try await statementStorageParameters.notificationAllowance() {
            return Int(allowance.maxSize)
        }

        logger.info("NotificationAllowance is not set on \(chainId); using the runtime default")

        return Int(ResourcesPallet.StatementAllowance.notificationDefault.maxSize)
    }
}

extension NotificationParametersProvider {
    static func period(atSeconds nowSeconds: UInt64, duration: UInt32) throws -> UInt32 {
        guard duration > 0 else {
            throw NotificationParametersError.zeroPeriodDuration
        }

        return UInt32(clamping: nowSeconds / UInt64(duration))
    }
}

private extension NotificationParametersProvider {
    func constant<T: Decodable>(_ path: ResourcesPallet.Constants) async throws -> T {
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chainId)
        let operation = StorageConstantOperation<T>(path: path(), fallbackValue: nil)
        operation.codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        return try await operation.asyncExecute()
    }
}
