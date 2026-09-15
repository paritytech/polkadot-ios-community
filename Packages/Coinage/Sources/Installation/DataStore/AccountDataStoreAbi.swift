import Foundation
import Web3Core

public enum AccountDataStoreAbiError: Error {
    case encodingFailed(function: String)
    case invalidAddress(Data)
}

/// ABI of the `AccountDataStore` contract (`account-data-store-contract`, `abi/AccountDataStore.json`).
public enum AccountDataStoreAbi {
    // registerCoinageInstallation(bytes record)
    private static let registerFunction = ABI.Element.Function(
        name: "registerCoinageInstallation",
        inputs: [.init(name: "record", type: .dynamicBytes)],
        outputs: [],
        constant: false,
        payable: false
    )

    // getCoinageInstallations(address owner) returns (bytes[])
    private static let getFunction = ABI.Element.Function(
        name: "getCoinageInstallations",
        inputs: [.init(name: "owner", type: .address)],
        outputs: [.init(name: "", type: .array(type: .dynamicBytes, length: 0))],
        constant: true,
        payable: false
    )

    public static func encodeRegisterInstallation(record: Data) throws -> Data {
        try encode(registerFunction, parameters: [record])
    }

    public static func encodeGetInstallations(owner: Data) throws -> Data {
        guard let address = EthereumAddress(owner) else {
            throw AccountDataStoreAbiError.invalidAddress(owner)
        }
        return try encode(getFunction, parameters: [address])
    }

    public static func decodeGetInstallations(output: Data) -> [Data] {
        guard let decoded = ABI.Element.function(getFunction).decodeReturnData(output) else { return [] }
        return decoded["0"] as? [Data] ?? []
    }
}

private extension AccountDataStoreAbi {
    static func encode(_ function: ABI.Element.Function, parameters: [Any]) throws -> Data {
        guard let encoded = ABI.Element.function(function).encodeParameters(parameters) else {
            throw AccountDataStoreAbiError.encodingFailed(function: function.name ?? "unknown")
        }
        return encoded
    }
}
