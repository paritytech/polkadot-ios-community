import Foundation
import Keystore_iOS
import Products

final class ProductsLocalStorage: ProductLocalStorageProtocol, @unchecked Sendable {
    private static let keyPrefix = "io.polkadotapp.ProductStorage"

    private let productId: String
    private let settingsManager: SettingsManagerProtocol

    init(productId: String, settingsManager: SettingsManagerProtocol) {
        self.productId = productId
        self.settingsManager = settingsManager
    }

    func read(key: String) async -> String? {
        settingsManager.string(for: storageKey(key))
    }

    func write(key: String, value: String) async {
        settingsManager.set(value: value, for: storageKey(key))
    }

    func clear(key: String) async {
        settingsManager.removeValue(for: storageKey(key))
    }

    private func storageKey(_ key: String) -> String {
        "\(Self.keyPrefix).\(productId).\(key)"
    }
}
