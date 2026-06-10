import Foundation

public protocol AuthorizeValueSigning {
    func canSign() -> Bool
    func sign(_ data: Data) throws -> Data
}
