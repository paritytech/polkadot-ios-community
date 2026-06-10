import Foundation
import SubstrateSdk

public struct Sr25519VrfSignature: Codable {
    enum CodingKeys: String, CodingKey {
        case preOutput
        case proof
    }

    @BytesCodable public var preOutput: Data
    @BytesCodable public var proof: Data

    public init(preOutput: Data, proof: Data) {
        self.preOutput = preOutput
        self.proof = proof
    }
}

public extension GamePallet {
    enum AirdropVrf: Codable {
        case account(Sr25519VrfSignature)
        case alias(AliasFields)

        public struct AliasFields: Codable {
            enum CodingKeys: String, CodingKey {
                case proof
                case ringIndex
                case revision
            }

            @BytesCodable public var proof: Data
            @StringCodable public var ringIndex: MembersPallet.RingIndex
            @StringCodable public var revision: MembersPallet.RevisionIndex

            public init(
                proof: Data,
                ringIndex: MembersPallet.RingIndex,
                revision: MembersPallet.RevisionIndex
            ) {
                _proof = BytesCodable(wrappedValue: proof)
                _ringIndex = StringCodable(wrappedValue: ringIndex)
                _revision = StringCodable(wrappedValue: revision)
            }
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(String.self)

            switch variant {
            case "Account":
                let vrf = try container.decode(Sr25519VrfSignature.self)
                self = .account(vrf)
            case "Alias":
                let fields = try container.decode(AliasFields.self)
                self = .alias(fields)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported AirdropVrf variant: \(variant)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()

            switch self {
            case let .account(vrf):
                try container.encode("Account")
                try container.encode(vrf)
            case let .alias(fields):
                try container.encode("Alias")
                try container.encode(fields)
            }
        }
    }
}
