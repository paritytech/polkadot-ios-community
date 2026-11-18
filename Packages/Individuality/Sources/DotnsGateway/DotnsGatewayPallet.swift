import Foundation
import SubstrateSdkExt

public enum DotnsGatewayPallet {
    public static let name = "DotnsGateway"
}

public extension DotnsGatewayPallet {
    enum Constants {
        case signingContext
    }
}

extension DotnsGatewayPallet.Constants: ConstantPathConvertible {
    public var name: String {
        switch self {
        case .signingContext:
            "SigningContext"
        }
    }

    public var moduleName: String { DotnsGatewayPallet.name }
}
