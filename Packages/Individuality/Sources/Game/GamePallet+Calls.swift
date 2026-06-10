import SubstrateSdk
import Foundation

public extension GamePallet {
    struct SignUpWithAccountCall: Codable {
        enum CodingKeys: String, CodingKey {
            case identifierKey = "identifier_key"
            case airdrop
        }

        @BytesCodable public var identifierKey: Data
        @NullCodable public var airdrop: AirdropVrf?

        public init(identifierKey: Data, airdrop: AirdropVrf?) {
            self.identifierKey = identifierKey
            self.airdrop = airdrop
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: GamePallet.name,
                callName: "sign_up_with_account",
                args: self
            )
        }
    }

    struct SignUpWithInviteCall: Codable {
        enum CodingKeys: String, CodingKey {
            case identifierKey = "identifier_key"
            case airdrop
        }

        @BytesCodable var identifierKey: Data
        @NullCodable var airdrop: AirdropVrf?

        public init(identifierKey: Data, airdrop: AirdropVrf?) {
            self.identifierKey = identifierKey
            self.airdrop = airdrop
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: GamePallet.name,
                callName: "sign_up_with_invite",
                args: self
            )
        }
    }

    struct SignUpWithAliasCall: Codable {
        enum CodingKeys: String, CodingKey {
            case identifierKey = "identifier_key"
            case statementAccount = "statement_account"
            case signature = "sig"
            case airdrop
        }

        @BytesCodable var identifierKey: Data
        @BytesCodable var statementAccount: AccountId
        let signature: MultiSignature
        @NullCodable var airdrop: AirdropVrf?

        public init(
            identifierKey: Data,
            statementAccount: AccountId,
            signature: MultiSignature,
            airdrop: AirdropVrf?
        ) {
            self.identifierKey = identifierKey
            self.statementAccount = statementAccount
            self.signature = signature
            self.airdrop = airdrop
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: GamePallet.name,
                callName: "sign_up_with_alias",
                args: self
            )
        }
    }

    struct ReportCall: Codable {
        enum CodingKeys: String, CodingKey {
            case fullReport = "full_report"
        }

        let fullReport: GamePallet.FullReport

        public init(fullReport: GamePallet.FullReport) {
            self.fullReport = fullReport
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: GamePallet.name,
                callName: "report",
                args: self
            )
        }
    }

    struct OffBoardCall: Codable {
        public init() {}

        public func runtimeCall() -> RuntimeCall<NoRuntimeArgs> {
            RuntimeCall(
                moduleName: GamePallet.name,
                callName: "offboard"
            )
        }
    }

    struct ClaimAirdropCall: Codable {
        enum CodingKeys: String, CodingKey {
            case gameIndex = "game_index"
            case beneficiary
        }

        @StringCodable public var gameIndex: UInt32
        @BytesCodable public var beneficiary: AccountId

        public init(gameIndex: UInt32, beneficiary: AccountId) {
            self.gameIndex = gameIndex
            self.beneficiary = beneficiary
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(moduleName: GamePallet.name, callName: "claim_airdrop", args: self)
        }
    }
}
