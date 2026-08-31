import AsyncExtensions
import Foundation
import Products

extension ProductsNativeApi {
    // The app is relaunched when the preferred language changes in Settings,
    // so the tag read at subscribe time is the whole subscription.
    //
    // `preferredLanguages` is already BCP 47, unlike `Locale.current.identifier`,
    // which uses the ICU underscore form.
    func subscribeLocale() async -> AnyAsyncSequence<String> {
        AsyncJustSequence<String>(Locale.preferredLanguages.first ?? "en")
            .eraseToAnyAsyncSequence()
    }
}
