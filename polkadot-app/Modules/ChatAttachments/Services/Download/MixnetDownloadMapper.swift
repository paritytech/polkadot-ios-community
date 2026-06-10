import CoreData
import Foundation
import Operation_iOS

enum MixnetDownloadMapperError: Error {
    case entityNotFound
}

final class MixnetDownloadMapper {
    var entityIdentifierFieldName: String { #keyPath(CDMixnetDownload.identifier) }

    typealias DataProviderModel = MixnetDownload
    typealias CoreDataEntity = CDMixnetDownload
}

extension MixnetDownloadMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        MixnetDownload(
            metadataHashHex: entity.identifier!,
            lastChunkIndex: entity.lastChunkIndex,
            totalChunks: entity.totalChunks,
            metadata: entity.metadata,
            downloadedBytes: entity.downloadedBytes
        )
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.lastChunkIndex = model.lastChunkIndex
        entity.totalChunks = model.totalChunks
        entity.metadata = model.metadata
        entity.downloadedBytes = model.downloadedBytes
    }
}

final class MixnetDownloadChunkIndexMapper {
    var entityIdentifierFieldName: String { #keyPath(CDMixnetDownload.identifier) }

    typealias DataProviderModel = MixnetDownloadChunkIndex
    typealias CoreDataEntity = CDMixnetDownload
}

extension MixnetDownloadChunkIndexMapper: CoreDataMapperProtocol {
    func transform(entity _: CoreDataEntity) throws -> DataProviderModel {
        throw CoreDataMapperError.unsupported
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MixnetDownloadMapperError.entityNotFound
        }

        entity.lastChunkIndex = model.lastChunkIndex
        entity.downloadedBytes = model.downloadedBytes
    }
}
