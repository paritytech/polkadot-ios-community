import CID
import Foundation
import Multicodec

enum UnixFsDecoderError: Error {
    case blockNotFound(CID)
    case invalidNode(String)
    case missingLinkName
}

/// Represents decoded UnixFS content types.
enum UnixFsContent {
    case directory
    case leaf(Data)
    case chunkedFile
}

/// Block data stored in the CAR file, with its codec.
struct BlockData {
    let data: Data
    let codec: Codecs
}

enum UnixFsDecoder {
    /// Reconstruct file tree from root CID and block map.
    /// Returns a dictionary mapping file paths to their content.
    static func reconstructFileTree(
        rootCid: CID,
        blocks: [CID: BlockData]
    ) throws -> [String: Data] {
        var result: [String: Data] = [:]
        try traverseNode(
            cid: rootCid,
            currentPath: "",
            blocks: blocks,
            result: &result
        )
        return result
    }

    // MARK: - Private

    private static func traverseNode(
        cid: CID,
        currentPath: String,
        blocks: [CID: BlockData],
        result: inout [String: Data]
    ) throws {
        guard let block = blocks[cid] else {
            throw UnixFsDecoderError.blockNotFound(cid)
        }

        // Raw codec blocks are leaf file content
        if block.codec == .raw {
            result[currentPath] = block.data
            return
        }

        // DAG-PB block: decode protobuf
        let dagPbNode = try DagPbDecoder.decode(from: block.data)

        // Decode UnixFS data if present
        let unixFs: UnixFsContent? = try dagPbNode.data.map { try decodeUnixFs($0) }

        switch unixFs {
        case .directory,
             .none:
            // Directory or node with links but no UnixFS: recurse into children
            for link in dagPbNode.links {
                guard let name = link.name else {
                    throw UnixFsDecoderError.missingLinkName
                }
                let childPath = currentPath.isEmpty ? name : "\(currentPath)/\(name)"
                try traverseNode(
                    cid: link.cid,
                    currentPath: childPath,
                    blocks: blocks,
                    result: &result
                )
            }

        case let .leaf(content):
            result[currentPath] = content

        case .chunkedFile:
            let assembled = try assembleChunkedFile(dagPbNode: dagPbNode, blocks: blocks)
            result[currentPath] = assembled
        }
    }

    private static func decodeUnixFs(_ data: Data) throws -> UnixFsContent {
        let proto = try UnixFsData(serializedBytes: data)

        switch proto.type {
        case .directory:
            return .directory

        case .raw:
            return .leaf(proto.data ?? Data())

        case .file:
            if !proto.blocksizes.isEmpty {
                return .chunkedFile
            }
            return .leaf(proto.data ?? Data())

        default:
            return .leaf(proto.data ?? Data())
        }
    }

    private static func assembleChunkedFile(
        dagPbNode: DagPbNode,
        blocks: [CID: BlockData]
    ) throws -> Data {
        var result = Data()

        for link in dagPbNode.links {
            guard let block = blocks[link.cid] else {
                throw UnixFsDecoderError.blockNotFound(link.cid)
            }

            if block.codec == .raw {
                // Raw codec: data is file content directly
                result.append(block.data)
            } else {
                // DAG-PB: may be a nested chunk or a leaf
                let childNode = try DagPbDecoder.decode(from: block.data)

                if !childNode.links.isEmpty {
                    // Nested chunks
                    let nested = try assembleChunkedFile(dagPbNode: childNode, blocks: blocks)
                    result.append(nested)
                } else if let data = childNode.data {
                    let unixFs = try UnixFsData(serializedBytes: data)
                    result.append(unixFs.data ?? Data())
                }
            }
        }

        return result
    }
}
