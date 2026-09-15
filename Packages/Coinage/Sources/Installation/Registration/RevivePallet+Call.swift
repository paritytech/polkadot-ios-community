import BigInt
import Foundation
import SubstrateSdk

public enum RevivePallet {
    public static let name = "Revive"

    /// `Revive.call`: runs `data` against the contract at `dest` from the signed origin.
    ///
    /// pallet-revive renamed `gas_limit` to `weight_limit` once `gas` came to mean Ethereum gas; both
    /// runtimes are live, so the name is read from metadata (``weightLimitArgumentName(in:)``).
    public struct CallCall: Codable {
        public static let callName = "call"

        public let dest: Data
        public let value: BigUInt
        public let weightLimit: Substrate.WeightV2
        public let weightLimitArgumentName: String
        public let storageDepositLimit: BigUInt
        public let data: Data

        public init(
            dest: Data,
            value: BigUInt,
            weightLimit: Substrate.WeightV2,
            weightLimitArgumentName: String,
            storageDepositLimit: BigUInt,
            data: Data
        ) {
            self.dest = dest
            self.value = value
            self.weightLimit = weightLimit
            self.weightLimitArgumentName = weightLimitArgumentName
            self.storageDepositLimit = storageDepositLimit
            self.data = data
        }

        public var runtimeCall: RuntimeCall<CallCall> {
            RuntimeCall(moduleName: RevivePallet.name, callName: Self.callName, args: self)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            dest = try container.decode(BytesCodable.self, forKey: .named(Keys.dest)).wrappedValue
            value = try container.decode(StringCodable<BigUInt>.self, forKey: .named(Keys.value)).wrappedValue
            let argumentName = container.contains(.named(Keys.weightLimit)) ? Keys.weightLimit : Keys.gasLimit
            weightLimitArgumentName = argumentName
            weightLimit = try container.decode(Substrate.WeightV2.self, forKey: .named(argumentName))
            storageDepositLimit = try container.decode(
                StringCodable<BigUInt>.self,
                forKey: .named(Keys.storageDepositLimit)
            ).wrappedValue
            data = try container.decode(BytesCodable.self, forKey: .named(Keys.data)).wrappedValue
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            try container.encode(BytesCodable(wrappedValue: dest), forKey: .named(Keys.dest))
            try container.encode(StringCodable(wrappedValue: value), forKey: .named(Keys.value))
            try container.encode(weightLimit, forKey: .named(weightLimitArgumentName))
            try container.encode(
                StringCodable(wrappedValue: storageDepositLimit),
                forKey: .named(Keys.storageDepositLimit)
            )
            try container.encode(BytesCodable(wrappedValue: data), forKey: .named(Keys.data))
        }

        enum Keys {
            static let dest = "dest"
            static let value = "value"
            static let weightLimit = "weight_limit"
            static let gasLimit = "gas_limit"
            static let storageDepositLimit = "storage_deposit_limit"
            static let data = "data"
        }
    }

    public static func weightLimitArgumentName(in metadata: any RuntimeMetadataProtocol) -> String {
        let arguments = metadata.getCall(from: name, with: CallCall.callName)?.arguments ?? []
        return arguments.contains { $0.name == CallCall.Keys.weightLimit }
            ? CallCall.Keys.weightLimit
            : CallCall.Keys.gasLimit
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }

    static func named(_ name: String) -> DynamicCodingKey {
        DynamicCodingKey(stringValue: name)! // swiftlint:disable:this force_unwrapping
    }
}
