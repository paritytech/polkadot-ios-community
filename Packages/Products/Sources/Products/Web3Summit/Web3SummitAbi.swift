import Foundation
import Web3Core

public enum Web3SummitAbi {
    // isCheckedIn(address account) returns (bool)
    private static let isCheckedInFunction = ABI.Element.Function(
        name: "isCheckedIn",
        inputs: [.init(name: "account", type: .address)],
        outputs: [.init(name: "", type: .bool)],
        constant: true,
        payable: false
    )

    public static func encodeIsCheckedIn(address: Data) -> Data {
        let element = ABI.Element.function(isCheckedInFunction)
        return element.encodeParameters([address.toHexWithPrefix()]) ?? Data()
    }

    public static func decodeIsCheckedIn(output: Data) -> Bool? {
        let element = ABI.Element.function(isCheckedInFunction)
        guard let decoded = element.decodeReturnData(output) else { return nil }
        return decoded["0"] as? Bool
    }
}
