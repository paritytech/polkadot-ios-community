import BigInt
import Coinage
import ExtrinsicService
import Foundation
import SubstrateSdk

/// Fee estimation for the installation registration extrinsic on the contract's chain, through the
/// app's extrinsic operation factory.
final class CoinageRegistrationFeeEstimator: RegistrationFeeEstimating, @unchecked Sendable {
    private let operationFactory: ExtrinsicOperationFactoryProtocol

    init(operationFactory: ExtrinsicOperationFactoryProtocol) {
        self.operationFactory = operationFactory
    }

    func estimateFee(
        _ builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> BigUInt {
        try await operationFactory
            .estimateFeeOperation(builder, origin: origin, payingIn: nil)
            .asyncExecute()
            .amount
    }
}
