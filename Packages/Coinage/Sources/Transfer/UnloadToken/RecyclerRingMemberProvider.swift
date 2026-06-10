import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import Individuality
import KeyDerivation

/// Provides recycler proof parameters.
///
/// Fetches the Bandersnatch public keys of included members and domain size in a specific recycler ring,
/// identified by denomination exponent and recycler index.
public final class RecyclerProofParamsProvider: RingProofParamsProviding {
    private let recyclerKey: RecyclerKey
    private let proofParamsFetcher: MembershipProofParamsFetching

    public init(
        recyclerKey: RecyclerKey,
        proofParamsFetcher: MembershipProofParamsFetching
    ) {
        self.recyclerKey = recyclerKey
        self.proofParamsFetcher = proofParamsFetcher
    }

    public func fetchParams(blockHash: BlockHashData?) async throws -> MembersProofParams {
        let key = recyclerKey
        let identifier = RecyclerCollectionIdentifier.identifier(for: key.exponent)

        return try await proofParamsFetcher.fetchOrError(
            for: key.index,
            collectionId: identifier,
            blockHash: blockHash
        )
    }
}
