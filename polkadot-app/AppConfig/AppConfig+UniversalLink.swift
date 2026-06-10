import Foundation

extension AppConfig {
    enum ProductUniversalLink {
        static let scheme = "https"
        static let shareRoot = "dot.li"

        static func url(for name: String) -> URL? {
            URL(string: "\(scheme)://\(name).\(shareRoot)")
        }
    }
}
