import Foundation
import Coinage
import CryptoKit
import KeyDerivation
import MessageExchangeKit
import NovaCrypto
import SDKLogger
import StatementStore
import SubstrateSdk

final class W3sStatementSubmitter {
    private let merchantKey: Data
    private let topic: Data
    private let paymentId: String
    private let amountString: String
    private let wallet: WalletManaging
    private let statementStoreSubmitter: StatementStoreSubmitting
    private let priorityFactory: StatementPriorityMaking
    private let logger: SDKLoggerProtocol?

    init(
        merchantKey: Data,
        topic: Data,
        paymentId: String,
        amountString: String,
        wallet: WalletManaging,
        statementStoreSubmitter: StatementStoreSubmitting,
        priorityFactory: StatementPriorityMaking = StatementPriorityFactory(),
        logger: SDKLoggerProtocol? = nil
    ) {
        self.merchantKey = merchantKey
        self.topic = topic
        self.paymentId = paymentId
        self.amountString = amountString
        self.wallet = wallet
        self.statementStoreSubmitter = statementStoreSubmitter
        self.priorityFactory = priorityFactory
        self.logger = logger
    }
}

extension W3sStatementSubmitter: TransferChatSubmitting {
    var isFailureFatal: Bool { true }

    func sendChatMessage(_ memo: TransferMemo, to _: AccountId) async throws {
        let envelope = try buildEnvelope(memo: memo)
        let envelopeBytes = try envelope.scaleEncoded()
        let signer = try makeSigner()

        let scaleEncodedPayload = try envelopeBytes.scaleEncoded()

        // Encoded priority carries the protocol-epoch second in the low 32 bits,
        // so adding 120 advances expiry by 2 minutes.
        let builder = StatementSubmitParametersBuilder(signer: signer, logger: logger)
            .addTopic1(topic)
            .addExpiry(priorityFactory.makeTimestampPriority() + 120)
            .addScaleEncodedPayload(scaleEncodedPayload)

        try await statementStoreSubmitter.submitStatement(with: builder)
    }
}

private extension W3sStatementSubmitter {
    func buildEnvelope(memo: TransferMemo) throws -> W3sPaymentEnvelope {
        let payload = W3sPaymentPayload(
            amount: amountString,
            timestampMs: UInt64(Date().timeIntervalSince1970 * 1_000),
            coins: memo.entries,
            paymentId: paymentId
        )
        let plaintext = try payload.scaleEncoded()

        let merchantPublicKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: merchantKey)
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let encryptorFactory = P256AESEncryptorFactory(privateKey: ephemeralPrivateKey)
        let encryptor = try encryptorFactory.makeEncryptor(
            remotePublicKey: merchantPublicKey.x963Representation
        )
        let ciphertext = try encryptor.encrypt(plaintext)

        return W3sPaymentEnvelope(
            encryptedData: ciphertext,
            ephemeralPublicKey: encryptorFactory.localPublicKey
        )
    }

    func makeSigner() throws -> StatementStoreKeypairSigner {
        let rawPublicKey = try wallet.getRawPublicKey()
        let publicKey = try SNPublicKey(rawData: rawPublicKey)
        let rawSecretKey = try wallet.fetchSignerSecret(for: publicKey)
        let secretKey = try SNPrivateKey(rawData: rawSecretKey)
        let keypair = SNKeypair(privateKey: secretKey, publicKey: publicKey)
        return StatementStoreKeypairSigner(keypair: keypair)
    }
}
