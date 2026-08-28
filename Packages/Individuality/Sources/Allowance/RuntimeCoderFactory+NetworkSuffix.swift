import Foundation
import SubstrateSdk
import SubstrateStorageQuery

extension RuntimeCoderFactoryProtocol {
    /// Reads the network suffix through the same coding factory used for the surrounding
    /// metadata reads, ensuring suffix and slot metadata remain on the same chain.
    func readNetworkSuffix(for constant: ConstantCodingPath) async throws -> Data {
        let operation = StorageConstantOperation<BytesCodable>(
            path: constant,
            fallbackValue: BytesCodable(wrappedValue: Data())
        )
        operation.codingFactory = self
        let suffix = try await operation.asyncExecute().wrappedValue
        guard !suffix.isEmpty else { throw AllowanceSlotAssignmentError.missingSuffix }
        return suffix
    }
}
