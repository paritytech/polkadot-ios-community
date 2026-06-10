import Foundation

public protocol ChatProductFileProviding: ProductFileProviding {
    func productEntryRelativePath(productId: ProductId) -> String
}

public final class CompositeProductFileProvider: ChatProductFileProviding {
    private let dotNsContentStorage: DotNsContentStorageProtocol
    private let chatScriptStorage: ChatScriptStorageProtocol
    private let contentHashCache: ContentHashCacheProtocol

    public init(
        dotNsContentStorage: DotNsContentStorageProtocol,
        chatScriptStorage: ChatScriptStorageProtocol,
        contentHashCache: ContentHashCacheProtocol
    ) {
        self.dotNsContentStorage = dotNsContentStorage
        self.chatScriptStorage = chatScriptStorage
        self.contentHashCache = contentHashCache
    }

    public func load(for productId: ProductId, relativePath: String) -> Data? {
        guard let contentHash = resolveContentHash(productId: productId),
              let data = dotNsContentStorage.loadContent(contentHash: contentHash, relativePath: relativePath)
        else {
            return chatScriptStorage.loadData(productId: productId, relativePath: relativePath)
        }

        return data
    }

    public func productEntryRelativePath(productId: ProductId) -> String {
        guard let contentHash = resolveContentHash(productId: productId),
              dotNsContentStorage.hasFileEntry(
                  contentHash: contentHash,
                  relativePath: dotNsContentStorage.chatEntrypointRelativePath()
              )
        else {
            return chatScriptStorage.chatEntrypointRelativePath()
        }

        return dotNsContentStorage.chatEntrypointRelativePath()
    }

    // MARK: - Private

    private func resolveContentHash(productId: ProductId) -> String? {
        contentHashCache.getContentHash(name: productId)
    }
}
