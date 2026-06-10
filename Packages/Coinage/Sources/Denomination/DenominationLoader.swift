import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import BigInt

protocol DenominationContextLoaderProtocol {
    /// Fetches denomination context for the given asset.
    /// - Parameter asset: The asset providing decimal precision
    /// - Returns: A denomination breakdown context configured for the asset
    func fetchContext(for asset: AssetProtocol) async throws -> DenominationBreakdownContext
}

final class DenominationContextLoader: DenominationContextLoaderProtocol {
    private let runtimeService: RuntimeCodingServiceProtocol

    init(runtimeService: RuntimeCodingServiceProtocol) {
        self.runtimeService = runtimeService
    }

    func fetchContext(for asset: AssetProtocol) async throws -> DenominationBreakdownContext {
        async let unit = runtimeService.fetchConstant(
            path: CoinagePallet.Constants.assetUnit(),
            type: BigUInt.self
        )

        async let maxExponent = runtimeService.fetchConstant(
            path: CoinagePallet.Constants.maximumExponent(),
            type: Int16.self
        )

        async let minExponent = runtimeService.fetchConstant(
            path: CoinagePallet.Constants.minimumExponent(),
            type: Int16.self
        )

        return try await DenominationBreakdownContext(
            unit: unit,
            precision: asset.decimalPrecision,
            maxExponent: maxExponent,
            minExponent: minExponent
        )
    }
}
