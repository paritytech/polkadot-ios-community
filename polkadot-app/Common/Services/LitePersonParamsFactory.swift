import Foundation
import Foundation_iOS
import Keystore_iOS
import SubstrateSdk
import NovaCrypto
import MessageExchangeKit
import KeyDerivation

struct LitePersonRegistrationParams {
    let accountId: AccountId
    let accountIdProofSignature: Data
    let personMemberKey: BandersnatchPubKey
    let membershipProofSignature: Data
    let chatPublicKey: Data
    let username: String
    let resourcesSignature: Data
}

protocol LitePersonParamsFactoryProtocol {
    func deriveLitePersonParams(
        for username: String,
        verifier: AccountId
    ) throws -> LitePersonRegistrationParams
}

enum LitePersonParamsFactoryError: Error {
    case invalidAccountId
    case invalidData
}

final class LitePersonParamsFactory {
    static let msgPrefix = "pop:people-lite:register using"

    let publicKey: SNPublicKey
    let accountIdSigner: SigningWrapperProtocol
    let liteVrfManager: BandersnatchKeyManaging
    let chatEncryptorFactory: MessageExchangeEncryptionMaking

    init(
        mainWallet: WalletManaging,
        liteVrfManager: BandersnatchKeyManaging,
        chatEncryptorManager: MessageExchangeEncryptionManaging
    ) throws {
        publicKey = try SNPublicKey(rawData: mainWallet.getRawPublicKey())

        accountIdSigner = DefaultSigningWrapper(secretProvider: mainWallet)

        self.liteVrfManager = liteVrfManager

        chatEncryptorFactory = try chatEncryptorManager.makeEncryptorFactory(
            ownEncryptionKeyId: Chat.Contact.Own.main().encryptionKeyId
        )
    }
}

private extension LitePersonParamsFactory {
    func prepareLitePersonSignatureData() throws -> Data {
        let msgPrefixData = try Self.msgPrefix.data(using: .utf8).mapOrThrow(
            LitePersonParamsFactoryError.invalidData
        )

        let memberKey = try liteVrfManager.getMemberKey()

        return msgPrefixData + publicKey.rawData() + memberKey
    }

    func prepareResourcesSignatureData(
        for username: String,
        chatPublicKey: Chat.PublicKey,
        verifier: AccountId
    ) throws -> Data {
        let resourcesSignatureDataCoder = ScaleEncoder()
        resourcesSignatureDataCoder.appendRaw(data: publicKey.rawData())
        resourcesSignatureDataCoder.appendRaw(data: verifier)
        resourcesSignatureDataCoder.appendRaw(data: chatPublicKey.rawData)
        try username.encode(scaleEncoder: resourcesSignatureDataCoder)

        // TODO: We might want reserve full username in future
        try ScaleOption<String>.none.encode(
            scaleEncoder: resourcesSignatureDataCoder
        )

        return resourcesSignatureDataCoder.encode()
    }
}

extension LitePersonParamsFactory: LitePersonParamsFactoryProtocol {
    func deriveLitePersonParams(
        for username: String,
        verifier: AccountId
    ) throws -> LitePersonRegistrationParams {
        let litePersonSignatureData = try prepareLitePersonSignatureData()

        let accountIdProofSignature = try accountIdSigner.sign(
            litePersonSignatureData,
            context: .rawBytes(publicKey)
        )
        .rawData()

        let personSignature = try liteVrfManager.sign(litePersonSignatureData)

        let rawChatPublicKey = chatEncryptorFactory.localPublicKey
        let chatPublicKey = try Chat.PublicKey(rawData: rawChatPublicKey)

        let resourcesSignatureData = try prepareResourcesSignatureData(
            for: username,
            chatPublicKey: chatPublicKey,
            verifier: verifier
        )

        let resourcesSignature = try accountIdSigner.sign(resourcesSignatureData, context: .rawBytes(publicKey))

        let memberKey = try liteVrfManager.getMemberKey()

        return LitePersonRegistrationParams(
            accountId: publicKey.rawData(),
            accountIdProofSignature: accountIdProofSignature,
            personMemberKey: memberKey,
            membershipProofSignature: personSignature,
            chatPublicKey: chatPublicKey.rawData,
            username: username,
            resourcesSignature: resourcesSignature.rawData()
        )
    }
}
