import Foundation
import CarParser

public enum DotNsResolverError: Error {
    case resolutionFailed(String)
    case contentHashNotFound(String)
    case carParseFailed(Error)
    case storageFailed(Error)
}

/// Protocol for resolving .dot domain names to local content directories.
public protocol DotNsResolverProtocol {
    /// Resolve a .dot domain name to a local URL containing the extracted content files.
    func resolveToLocalURL(dotNsName: String) async throws -> URL

    /// Fetch a metadata entry for a .dot domain (e.g., "url", "description").
    func getMetadataEntry(dotNsName: String, key: String) async throws -> String?

    /// Check if the resolved content for a .dot domain contains a chat worker entry.
    func hasChatEntry(_ dotnsName: String) -> Bool

    /// Clear all cached content and hash mappings.
    func clearCache() throws
}

public final class DotNsResolver: DotNsResolverProtocol {
    private let contractApi: DotNsContractApiProtocol
    private let carFetcher: CarFetcherProtocol
    private let contentStorage: DotNsContentStorageProtocol
    private let contentHashCache: ContentHashCacheProtocol

    public init(
        contractApi: DotNsContractApiProtocol,
        carFetcher: CarFetcherProtocol,
        contentStorage: DotNsContentStorageProtocol,
        contentHashCache: ContentHashCacheProtocol
    ) {
        self.contractApi = contractApi
        self.carFetcher = carFetcher
        self.contentStorage = contentStorage
        self.contentHashCache = contentHashCache
    }

    // TODO: Current implementation always fetch content hash from contract.
    // Target solution should warn a user if hash changed monitoring the cache
    public func resolveToLocalURL(dotNsName: String) async throws -> URL {
        // 1. Resolve content hash from the on-chain resolver
        let contentHashBytes = try await contractApi.resolveContentHash(dotNsName: dotNsName)
        let hexHash = contentHashBytes.toHex()

        // 2. Check if content is already cached on disk
        if let cachedDir = contentStorage.getContentDirectory(contentHash: hexHash) {
            contentHashCache.putContentHash(name: dotNsName, hash: hexHash)
            return cachedDir
        }

        // 3. Fetch CAR archive from IPFS
        let carBytes = try await carFetcher.fetchCar(contentHash: contentHashBytes)

        // 4. Parse CAR archive into file tree
        let archive: UnpackedArchive
        do {
            archive = try CarParser.parse(data: carBytes)
        } catch {
            throw DotNsResolverError.carParseFailed(error)
        }

        // 5. Save files to disk
        do {
            try contentStorage.saveContent(contentHash: hexHash, files: archive.files)
        } catch {
            throw DotNsResolverError.storageFailed(error)
        }

        // 6. Update cache
        contentHashCache.putContentHash(name: dotNsName, hash: hexHash)

        // 7. Return content directory URL
        guard let contentDir = contentStorage.getContentDirectory(contentHash: hexHash) else {
            throw DotNsResolverError.resolutionFailed("Failed to retrieve saved content for \(dotNsName)")
        }

        return contentDir
    }

    public func hasChatEntry(_ dotnsName: String) -> Bool {
        guard let contentHash = contentHashCache.getContentHash(name: dotnsName) else {
            return false
        }
        return contentStorage.hasFileEntry(
            contentHash: contentHash,
            relativePath: contentStorage.chatEntrypointRelativePath()
        )
    }

    public func getMetadataEntry(dotNsName: String, key: String) async throws -> String? {
        try await contractApi.getMetadata(dotNsName: dotNsName, key: key)
    }

    public func clearCache() throws {
        try contentStorage.deleteAll()
        contentHashCache.clearAll()
    }
}
