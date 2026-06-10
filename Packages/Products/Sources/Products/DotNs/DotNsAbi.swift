import Foundation
import Web3Core

public enum DotNsAbi {
    // contenthash(bytes32 node) returns (bytes)
    private static let contenthashFunction = ABI.Element.Function(
        name: "contenthash",
        inputs: [.init(name: "node", type: .bytes(length: 32))],
        outputs: [.init(name: "", type: .dynamicBytes)],
        constant: true,
        payable: false
    )

    // text(bytes32 node, string key) returns (string)
    private static let textFunction = ABI.Element.Function(
        name: "text",
        inputs: [.init(name: "node", type: .bytes(length: 32)), .init(name: "key", type: .string)],
        outputs: [.init(name: "", type: .string)],
        constant: true,
        payable: false
    )

    public static func encodeContentHash(node: Data) -> Data {
        let element = ABI.Element.function(contenthashFunction)
        return element.encodeParameters([node]) ?? Data()
    }

    public static func decodeContentHash(output: Data) -> Data? {
        let element = ABI.Element.function(contenthashFunction)
        guard let decoded = element.decodeReturnData(output) else { return nil }
        return decoded["0"] as? Data
    }

    public static func encodeText(node: Data, key: String) -> Data {
        let element = ABI.Element.function(textFunction)
        return element.encodeParameters([node, key]) ?? Data()
    }

    public static func decodeText(output: Data) -> String? {
        let element = ABI.Element.function(textFunction)
        guard let decoded = element.decodeReturnData(output) else { return nil }
        let result = decoded["0"] as? String
        return result?.isEmpty == true ? nil : result
    }
}
