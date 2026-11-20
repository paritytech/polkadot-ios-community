import Coinage
import Keystore_iOS
import Testing

@testable import polkadot_app

@Suite("Coinage recycling strategy store")
struct CoinageRecyclingStrategyStoreTests {
    @Test(
        "The privacy mode falls back to Balanced only when none is stored",
        arguments: [
            (nil as String?, RecyclingStrategyType.balanced),
            ("minPrivacy", .minPrivacy),
            ("maxPrivacy", .maxPrivacy)
        ]
    )
    func fallsBackToBalancedOnlyWhenNoneStored(storedValue: String?, expected: RecyclingStrategyType) {
        let settings = InMemorySettingsManager()
        if let storedValue {
            settings.set(string: storedValue, for: .coinageRecyclingStrategy)
        }

        let store = CoinageRecyclingStrategyStore(settingsManager: settings)

        #expect(store.strategy == expected)
    }
}
