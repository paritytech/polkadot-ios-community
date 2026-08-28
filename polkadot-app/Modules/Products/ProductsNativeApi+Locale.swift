import AsyncExtensions
import Foundation
import Products

extension ProductsNativeApi {
    func subscribeLocale() async -> AnyAsyncSequence<String> {
        AsyncStream<String> { continuation in
            let task = Task {
                continuation.yield(Self.currentLanguageTag())

                let changes = NotificationCenter.default.notifications(
                    named: NSLocale.currentLocaleDidChangeNotification
                )
                for await _ in changes {
                    continuation.yield(Self.currentLanguageTag())
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyAsyncSequence()
    }
}

private extension ProductsNativeApi {
    // The app ships no language picker, so the system preference is the
    // selection. `preferredLanguages` is already BCP 47, unlike
    // `Locale.current.identifier`, which uses the ICU underscore form.
    static func currentLanguageTag() -> String {
        Locale.preferredLanguages.first ?? "en"
    }
}
