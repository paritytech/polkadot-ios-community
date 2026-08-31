import Foundation
import AsyncExtensions

protocol LocaleProviding: Sendable {
    /// Emits the user's current UI language as a BCP 47 tag, then again on every
    /// change.
    func subscribe() -> AnyAsyncSequence<String>
}

/// Reports the user's preferred language from the system, re-emitting when the
/// user changes their language or region settings.
final class SystemLocaleProvider: LocaleProviding, @unchecked Sendable {
    static let shared = SystemLocaleProvider()

    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func subscribe() -> AnyAsyncSequence<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))

        continuation.yield(Self.currentLanguageTag())

        let observer = notificationCenter.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            continuation.yield(Self.currentLanguageTag())
        }

        continuation.onTermination = { [notificationCenter] _ in
            notificationCenter.removeObserver(observer)
        }

        return stream.eraseToAnyAsyncSequence()
    }

    static func currentLanguageTag() -> String {
        if let preferred = Locale.preferredLanguages.first, !preferred.isEmpty {
            return preferred
        }

        return Locale.current.identifier(.bcp47)
    }
}
