import Foundation

/// Key-value storage scoped to a single product, used by product scripts
/// via the `localStorageRead` / `localStorageWrite` / `localStorageClear` host API.
public protocol ProductLocalStorageProtocol: Sendable {
    func read(key: String) async -> String?
    func write(key: String, value: String) async
    func clear(key: String) async
}
