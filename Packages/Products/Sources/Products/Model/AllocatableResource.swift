import Foundation
import SubstrateSdk

public enum AllocatableResource: Equatable {
    case statementStoreAllowance
    case bulletInAllowance
    case smartContractAllowance(dest: UInt32)
    case autoSigning
}

public enum AllocationOutcome: Equatable {
    case allocated(AllocatedResource)
    case rejected
    case notAvailable
}

public enum AllocatedResource: Equatable {
    case autoSigning(AutoSigningSecrets)
    case statementStoreAllowance(privateKey: Data)
    case bulletInAllowance(privateKey: Data)
    case smartContractAllowance
}

public struct AutoSigningSecrets: Equatable {
    public let productDerivationSecret: String
    public let productRootPrivateKey: Data

    public init(productDerivationSecret: String, productRootPrivateKey: Data) {
        self.productDerivationSecret = productDerivationSecret
        self.productRootPrivateKey = productRootPrivateKey
    }
}
