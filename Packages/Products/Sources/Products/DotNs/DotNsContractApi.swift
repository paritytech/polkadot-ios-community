import Foundation
import SubstrateSdk

public enum DotNsContractError: Error {
    case contentHashNotFound
    case contentHashTooShort
    case unsupportedEip1577Prefix(Data)
    case contractCallFailed(Error)
    case runtimeApiNotFound
    case callFailed(JSON)
}

/// Protocol for interacting with the DotNS resolver smart contract on Asset Hub.
public protocol DotNsContractApiProtocol {
    /// Resolve a .dot domain name to its IPFS content hash (raw CID bytes, EIP-1577 prefix stripped).
    func resolveContentHash(dotNsName: String) async throws -> Data

    /// Fetch a metadata entry (e.g. "url", "description") for a .dot domain.
    func getMetadata(dotNsName: String, key: String) async throws -> String?
}

/// EIP-1577 prefix constants.
public enum Eip1577 {
    /// IPFS namespace prefix: uvarint-encoded 0xe3 = [0xe3, 0x01]
    public static let ipfsPrefix = Data([0xE3, 0x01])

    /// Strip the EIP-1577 IPFS prefix from a content hash.
    public static func stripPrefix(_ contentHash: Data) throws -> Data {
        guard contentHash.count > ipfsPrefix.count else {
            throw DotNsContractError.contentHashTooShort
        }

        let prefix = contentHash.prefix(ipfsPrefix.count)
        guard prefix == ipfsPrefix else {
            throw DotNsContractError.unsupportedEip1577Prefix(Data(prefix))
        }

        return Data(contentHash.dropFirst(ipfsPrefix.count))
    }
}
