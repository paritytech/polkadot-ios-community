import Foundation
import SubstrateSdk

struct RegisterUsernameParameters: Encodable {
    let username: String
    let preferredDigits: String?
    let candidateAccountId: AccountAddress
    @HexCodable var candidateSignature: Data
    @HexCodable var ringVrfKey: Data
    @HexCodable var proofOfOwnership: Data
    @HexCodable var identifierKey: Data
    @HexCodable var consumerRegistrationSignature: Data
}
