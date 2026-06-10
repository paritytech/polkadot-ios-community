import Foundation
import SubstrateSdk
import SubstrateSdkExt
import BigInt
import Individuality

extension CoinagePallet {
    enum Calls {}
}

extension CoinagePallet.Calls {
    /// Batched variant of `load_recycler_with_external_asset_unpaid`.
    /// Origin must be `InfallibleUnpaidSigned`. The transaction extension validates
    /// each item and checks member-key uniqueness + balance coverage for the sum.
    /// Dispatch is atomic — all items succeed or the whole call fails. The call is free.
    struct LoadExternalAssetUnpaidBatch: RuntimeCallConvertible {
        var moduleName: String { CoinagePallet.name }
        var name: String { "load_recycler_with_external_asset_unpaid_batch" }

        let items: [UnpaidLoadInput]

        struct UnpaidLoadInput: Codable {
            @StringCodable var value: Int16
            let preservation: Preservation
            @BytesCodable var memberKey: Data
            @BytesCodable var proofOfOwnership: Data

            enum Preservation: Codable {
                case protect
                case preserve
                case expendable

                init(from decoder: any Decoder) throws {
                    var container = try decoder.unkeyedContainer()
                    let state = try container.decode(String.self)

                    switch state {
                    case "Protect": self = .protect
                    case "Preserve": self = .preserve
                    case "Expendable": self = .expendable
                    default:
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Unsupported choice: \(state)"
                        )
                    }
                }

                func encode(to encoder: any Encoder) throws {
                    var container = encoder.unkeyedContainer()
                    switch self {
                    case .protect:
                        try container.encode("Protect")
                        try container.encode(JSON.null)
                    case .preserve:
                        try container.encode("Preserve")
                        try container.encode(JSON.null)
                    case .expendable:
                        try container.encode("Expendable")
                        try container.encode(JSON.null)
                    }
                }
            }
        }
    }

    /// split call - splits a coin into multiple outputs
    /// Origin: AsCoin (signs with coin keypair)
    struct Split: RuntimeCallConvertible {
        var moduleName: String { CoinagePallet.name }
        var name: String { "split" }

        let splitInto: [SplitDestination]

        init(splitInto: [SplitDestination]) {
            self.splitInto = splitInto
        }

        struct SplitDestination: Codable, Equatable {
            let exponent: Int16
            let accounts: [BytesCodable]

            init(exponent: Int16, accounts: [Data]) {
                self.exponent = exponent
                self.accounts = accounts.map { BytesCodable(wrappedValue: $0) }
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.unkeyedContainer()
                try container.encode(StringCodable(wrappedValue: exponent))
                try container.encode(accounts)
            }
        }

        enum CodingKeys: String, CodingKey {
            case splitInto = "split_into"
        }
    }

    /// unload_recycler_into_coins call - atomically unloads vouchers AND splits into target denominations
    /// Origin: AsUnloadToken (Ring-VRF proof, no traditional signer)
    struct UnloadRecyclerIntoCoins: RuntimeCallConvertible {
        var moduleName: String { CoinagePallet.name }
        var name: String { "unload_recycler_into_coins" }

        let aliases: [BytesCodable]

        /// Denomination exponent (all vouchers must have same value)
        @StringCodable var value: Int8

        /// Recycler index
        @StringCodable var index: UInt32

        /// Recycler revision (must match on-chain)
        @StringCodable var revision: UInt32

        let splitInto: [Split.SplitDestination]

        @StringCodable var maxFee: Balance

        init(
            aliases: [Data],
            value: Int8,
            index: UInt32,
            revision: UInt32,
            splitInto: [Split.SplitDestination],
            maxFee: Balance = 0 // pay no fees by default
        ) {
            self.aliases = aliases.map { BytesCodable(wrappedValue: $0) }
            self.value = value
            self.index = index
            self.revision = revision
            self.splitInto = splitInto
            self.maxFee = maxFee
        }

        enum CodingKeys: String, CodingKey {
            case aliases
            case value
            case index
            case revision
            case splitInto = "split_into"
            case maxFee = "max_fee"
        }
    }

    /// load_recycler_with_coin call - loads a coin into the recycler for age renewal
    /// Origin: AsCoin (signs with coin keypair)
    struct LoadRecyclerWithCoin: RuntimeCallConvertible {
        var moduleName: String { CoinagePallet.name }
        var name: String { "load_recycler_with_coin" }

        @BytesCodable var memberKey: Data
        @BytesCodable var proofOfOwnership: Data

        enum CodingKeys: String, CodingKey {
            case memberKey = "member_key"
            case proofOfOwnership = "proof_of_ownership"
        }
    }

    /// unload_recycler_into_external_asset — unloads all voucher value as external asset
    /// to a destination. Used when the full group value goes toward the payment (no surplus).
    /// Origin: AsUnloadToken
    struct UnloadRecyclerIntoExternalAsset: RuntimeCallConvertible {
        var moduleName: String { CoinagePallet.name }
        var name: String { "unload_recycler_into_external_asset" }

        let aliases: [BytesCodable]
        @StringCodable var value: Int8
        @StringCodable var index: UInt32
        @StringCodable var revision: UInt32
        @BytesCodable var to: AccountId

        init(
            aliases: [Data],
            value: Int8,
            index: UInt32,
            revision: UInt32,
            to: AccountId
        ) {
            self.aliases = aliases.map { BytesCodable(wrappedValue: $0) }
            self.value = value
            self.index = index
            self.revision = revision
            self.to = to
        }

        enum CodingKeys: String, CodingKey {
            case aliases
            case value
            case index
            case revision
            case to
        }
    }

    /// unload_recycler_into_external_asset_and_vouchers — atomically unloads vouchers,
    /// transfers an external asset amount to a destination, and mints new vouchers from surplus.
    /// Origin: AsUnloadToken
    struct UnloadRecyclerIntoExternalAssetAndVouchers: RuntimeCallConvertible {
        var moduleName: String { CoinagePallet.name }
        var name: String { "unload_recycler_into_external_asset_and_vouchers" }

        let aliases: [BytesCodable]
        @StringCodable var value: Int8
        @StringCodable var index: UInt32
        @StringCodable var revision: UInt32
        @BytesCodable var to: AccountId
        @StringCodable var externalAssetAmount: Balance
        let newVouchers: [NewVoucher]

        init(
            aliases: [Data],
            value: Int8,
            index: UInt32,
            revision: UInt32,
            to: AccountId,
            externalAssetAmount: Balance,
            newVouchers: [NewVoucher]
        ) {
            self.aliases = aliases.map { BytesCodable(wrappedValue: $0) }
            self.value = value
            self.index = index
            self.revision = revision
            self.to = to
            self.externalAssetAmount = externalAssetAmount
            self.newVouchers = newVouchers
        }

        struct NewVoucher: Codable {
            let coinValue: Int8
            let memberKey: Data

            func encode(to encoder: any Encoder) throws {
                var container = encoder.unkeyedContainer()
                try container.encode(StringCodable(wrappedValue: coinValue))
                try container.encode(BytesCodable(wrappedValue: memberKey))
            }
        }

        enum CodingKeys: String, CodingKey {
            case aliases
            case value
            case index
            case revision
            case to
            case externalAssetAmount = "external_asset_amount"
            case newVouchers = "new_vouchers"
        }
    }

    struct Transfer: RuntimeCallConvertible {
        var moduleName: String { CoinagePallet.name }
        var name: String { "transfer" }

        @BytesCodable var to: AccountId
    }
}
