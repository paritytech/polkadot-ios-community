import Foundation
import SubstrateSdk
import ExtrinsicService

public enum ValueTransferAuthPallet {}

public extension ValueTransferAuthPallet {
    final class TransactionExtension {
        public let extrinsicVersion: Extrinsic.Version
        public let signer: AuthorizeValueSigning?

        public init(
            extrinsicVersion: Extrinsic.Version = .V5(extensionVersion: 0),
            signer: AuthorizeValueSigning? = nil
        ) {
            self.extrinsicVersion = extrinsicVersion
            self.signer = signer
        }
    }
}

extension ValueTransferAuthPallet.TransactionExtension: TransactionExtending {
    public var txExtensionId: String { "AuthorizeValueTransfer" }

    public func implicit(
        using _: DynamicScaleEncodingFactoryProtocol,
        metadata _: RuntimeMetadataProtocol,
        context _: RuntimeJsonContext?
    ) throws -> Data? {
        nil
    }

    public func explicit(
        for implication: TransactionExtension.Implication,
        encodingFactory: DynamicScaleEncodingFactoryProtocol,
        metadata: RuntimeMetadataProtocol,
        context: RuntimeJsonContext?
    ) throws -> TransactionExtension.Explicit? {
        guard let signer, signer.canSign() else {
            return try TransactionExtension.Explicit(
                from: .null,
                txExtensionId: txExtensionId,
                metadata: metadata
            )
        }

        let payloadFactory = ImplicationSignaturePayloadFactory(
            extrinsicVersion: extrinsicVersion
        )
        let payload = try payloadFactory.createPayload(
            from: implication,
            using: encodingFactory
        )
        let hash = try payload.blake2b32()

        let signatureData = try signer.sign(hash)

        let json = try signatureData
            .toScaleCompatibleJSON(with: context?.toRawContext())

        return try TransactionExtension.Explicit(
            from: json,
            txExtensionId: txExtensionId,
            metadata: metadata
        )
    }
}
