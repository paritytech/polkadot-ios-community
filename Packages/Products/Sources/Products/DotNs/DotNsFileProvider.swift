import Foundation

public final class DotNsFileProvider: ProductFileProviding {
    private let contentDirectory: URL

    public init(contentDirectory: URL) {
        self.contentDirectory = contentDirectory
    }

    public func load(for _: ProductId, relativePath: String) -> Data? {
        let fileURL = contentDirectory.appendingPathComponent(relativePath)
        return try? Data(contentsOf: fileURL)
    }
}
