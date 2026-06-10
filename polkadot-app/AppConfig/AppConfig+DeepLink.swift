import Foundation

extension AppConfig {
    #if F_DEV
        private static let appDeepLinkScheme: String = "polkadotappdev"
    #else
        private static let appDeepLinkScheme: String = "polkadotapp"
    #endif
    enum DeepLink {
        static var scheme: String { appDeepLinkScheme }

        static func chat(_ chatId: Chat.Id, force: Bool) -> URL {
            let idPart = "id=\(chatId.rawRepresentation)"
            let forcePart = "force=\(force)"

            return URL(string: AppConfig.appDeepLinkScheme + "://chat?\(idPart)&\(forcePart)")!
        }

        static func reserve() -> URL {
            URL(string: AppConfig.appDeepLinkScheme + "://tattoo")!
        }

        static func tattooUploading() -> URL {
            URL(string: AppConfig.appDeepLinkScheme + "://tattoo/uploading")!
        }

        static func game(intendedGameIndex: Int? = nil) -> URL {
            var components = URLComponents()
            components.scheme = AppConfig.appDeepLinkScheme
            components.host = "game"

            if let intendedGameIndex {
                components.queryItems = [
                    URLQueryItem(name: PushNotificationKeys.gameIndex, value: "\(intendedGameIndex)")
                ]
            }

            return components.url!
        }

        static func players(game: UInt32, gameDate: Date) -> URL {
            let idPart = "id=\(game)"
            let datePart = "date=\(gameDate.formatted(.iso8601))"

            return URL(string: AppConfig.appDeepLinkScheme + "://players?\(idPart)&\(datePart)")!
        }

        static func fiatOnramp(sessionId: String) -> URL {
            URL(string: AppConfig.appDeepLinkScheme + "://fiatOnramp/buySuccess?sessionId=\(sessionId)")!
        }
    }
}
