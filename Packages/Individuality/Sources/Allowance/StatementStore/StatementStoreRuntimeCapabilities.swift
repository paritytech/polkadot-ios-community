import Foundation
import SubstrateSdk
import ChainStore
import StructuredConcurrency

/// Which generation of the statement-store slot API the connected runtime speaks.
public protocol StatementStoreRuntimeCapabilities {
    /// Whether occupied slots are taken over with `replace_statement_store_account`
    /// (individuality-community #234); older runtimes replace through `set_statement_store_account`
    /// under a cooldown instead.
    func supportsSlotReplacement() async throws -> Bool
}

public final class MetadataStatementStoreRuntimeCapabilities: StatementStoreRuntimeCapabilities {
    private let chainId: ChainId
    private let chainRegistry: ChainResourceProtocol

    public init(chainId: ChainId, chainRegistry: ChainResourceProtocol) {
        self.chainId = chainId
        self.chainRegistry = chainRegistry
    }

    public func supportsSlotReplacement() async throws -> Bool {
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        return codingFactory.metadata.getCall(
            from: ResourcesPallet.name,
            with: ResourcesPallet.ReplaceStatementStoreAccountCall.callName
        ) != nil
    }
}
