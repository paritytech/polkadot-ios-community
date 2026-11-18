import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import ChainStore
import StructuredConcurrency

public protocol StatementStorageParametersProviding: Sendable {
    /// The notification allowance the chain exposes: the pallet constant on runtimes that still export it,
    /// otherwise the value governance set in `pallet_parameters`; `nil` while the runtime default applies.
    func notificationAllowance() async throws -> ResourcesPallet.StatementAllowance?
}

public extension ResourcesPallet.StatementAllowance {
    /// The People runtime's `NotificationAllowance` default (`runtimes/next-people-paseo/src/parameters.rs`),
    /// in force while governance has not set the parameter; no metadata exposes it.
    static let notificationDefault = ResourcesPallet.StatementAllowance(maxCount: 1, maxSize: 5 * 1_024 / 2)
}

public final class StatementStorageParametersProvider: StatementStorageParametersProviding, @unchecked Sendable {
    private let chainId: ChainId
    private let chainRegistry: ChainResourceProtocol
    private let storageRequestFactory: StorageRequestFactoryProtocol

    public init(
        chainId: ChainId,
        chainRegistry: ChainResourceProtocol,
        storageRequestFactory: StorageRequestFactoryProtocol
    ) {
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.storageRequestFactory = storageRequestFactory
    }

    public func notificationAllowance() async throws -> ResourcesPallet.StatementAllowance? {
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        let constantPath = ResourcesPallet.Constants.notificationAllowance()

        if codingFactory.getConstant(for: constantPath) != nil {
            return try await constant(at: constantPath, codingFactory: codingFactory)
        }

        return try await parameter(codingFactory: codingFactory)
    }
}

private extension StatementStorageParametersProvider {
    func constant(
        at path: ConstantCodingPath,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> ResourcesPallet.StatementAllowance {
        let operation = StorageConstantOperation<ResourcesPallet.StatementAllowance>(path: path, fallbackValue: nil)
        operation.codingFactory = codingFactory

        return try await operation.asyncExecute()
    }

    func parameter(codingFactory: RuntimeCoderFactoryProtocol) async throws -> ResourcesPallet.StatementAllowance? {
        let connection = try chainRegistry.getRpcConnectionOrError(for: chainId)

        let key = ParametersPallet.StatementStorageKey(parameter: .notificationAllowance)
        let responses: [StorageResponse<ParametersPallet.StatementStorageValue<ResourcesPallet.StatementAllowance>>]
        responses = try await storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [key] },
            factory: { codingFactory },
            storagePath: ParametersPallet.parameters
        )
        .asyncExecute()

        return responses.first?.value?.value
    }
}
