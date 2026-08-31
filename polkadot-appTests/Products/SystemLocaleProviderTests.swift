import Testing
import Foundation
@testable import polkadot_app

@Suite("SystemLocaleProvider")
struct SystemLocaleProviderTests {
    @Test("emits the current language tag on subscribe, then again on a locale change")
    func emitsCurrentThenOnChange() async throws {
        let center = NotificationCenter()
        let provider = SystemLocaleProvider(notificationCenter: center)

        var iterator = provider.subscribe().makeAsyncIterator()

        let first = try #require(await iterator.next())
        #expect(first == SystemLocaleProvider.currentLanguageTag())

        // A locale change re-emits. The observer runs synchronously on post.
        center.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        let second = try #require(await iterator.next())
        #expect(second == SystemLocaleProvider.currentLanguageTag())
    }
}
