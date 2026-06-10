import Foundation

extension Chat {
    enum PublicKeyError: Error {
        case invalidRemoteKeySize(Int)
    }

    struct PublicKey {
        static let keySize = 65

        let rawData: Data

        init(rawData: Data) throws {
            guard rawData.count == Self.keySize else {
                throw PublicKeyError.invalidRemoteKeySize(rawData.count)
            }

            self.rawData = rawData
        }
    }
}
