import Foundation
import ExtrinsicService
import KeyDerivation
import SubstrateSdkExt
import Individuality

/// Submits on-chain coin transfer extrinsics.
protocol CoinTransferSubmitting: Sendable {
    /// Submits a transfer extrinsic moving a coin from sender to a new destination.
    ///
    /// - Parameters:
    ///   - senderPrivateKey: Private key of the source coin owner.
    ///   - senderPublicKey: Public key of the source coin owner.
    ///   - destinationCoin: Pre-allocated destination coin to transfer into.
    /// - Returns: The destination coin on success.
    func submitTransfer(
        senderPrivateKey: Data,
        senderPublicKey: Data,
        destinationCoin: Coin
    ) async throws -> Coin
}

/// Default implementation that builds and submits a `CoinagePallet.Calls.Transfer` extrinsic.
final class CoinTransferSubmitter: CoinTransferSubmitting, @unchecked Sendable {
    private let originFactory: any OriginCreating
    private let extrinsicMonitor: any ExtrinsicSubmitMonitorFactoryProtocol
    private let coinKeyFactory: any CoinKeyDeriving

    init(
        originFactory: any OriginCreating,
        extrinsicMonitor: any ExtrinsicSubmitMonitorFactoryProtocol,
        coinKeyFactory: any CoinKeyDeriving
    ) {
        self.originFactory = originFactory
        self.extrinsicMonitor = extrinsicMonitor
        self.coinKeyFactory = coinKeyFactory
    }

    func submitTransfer(
        senderPrivateKey: Data,
        senderPublicKey: Data,
        destinationCoin: Coin
    ) async throws -> Coin {
        let coinWallet = try CoinDerivedWallet(
            privateKey: senderPrivateKey,
            publicKey: senderPublicKey
        )
        let origin = try originFactory.createAsCoinOrigin(for: coinWallet)
        let destinationPublicKey = try coinKeyFactory.derivePublicKey(for: destinationCoin)
        let call = CoinagePallet.Calls.Transfer(to: destinationPublicKey)
        let builder: ExtrinsicBuilderClosure = { builder in
            try builder.adding(call: call.callAsFunction())
        }

        let result = try await extrinsicMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: builder,
            origin: origin,
            params: .empty
        ).asyncExecute()

        switch result.status {
        case .success:
            return destinationCoin
        case let .failure(error):
            throw error.error
        }
    }
}
