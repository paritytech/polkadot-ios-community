import Foundation
import Keystore_iOS
import SubstrateSdk

protocol CoinageIndexstoreProtocol {
    func getNextIndex() throws -> UInt32
    func getCurrentIndex() throws -> UInt32?
    func setCurrentIndex(_ index: UInt32) throws

    var storageKey: String { get }
    var storage: KeystoreProtocol { get }
}

extension CoinageIndexstoreProtocol {
    func getNextIndex() throws -> UInt32 {
        let exists = try storage.checkKey(for: storageKey)
        guard exists else {
            try storage.saveKey(UInt32(0).scaleEncoded(), with: storageKey)
            return 0
        }

        let data = try storage.fetchKey(for: storageKey)
        let decoder = try ScaleDecoder(data: data)
        var index = try UInt32(scaleDecoder: decoder)
        index += 1
        try storage.saveKey(index.scaleEncoded(), with: storageKey)

        return index
    }

    func getCurrentIndex() throws -> UInt32? {
        guard try storage.checkKey(for: storageKey) else { return nil }
        let data = try storage.fetchKey(for: storageKey)
        let decoder = try ScaleDecoder(data: data)
        return try UInt32(scaleDecoder: decoder)
    }

    func setCurrentIndex(_ index: UInt32) throws {
        try storage.saveKey(index.scaleEncoded(), with: storageKey)
    }
}

final class CoinIndexstore: CoinageIndexstoreProtocol {
    let storage: KeystoreProtocol
    let storageKey = "coin-index"

    init(storage: KeystoreProtocol) {
        self.storage = storage
    }
}

final class VoucherIndexstore: CoinageIndexstoreProtocol {
    let storage: KeystoreProtocol
    let storageKey = "voucher-index"

    init(storage: KeystoreProtocol) {
        self.storage = storage
    }
}
