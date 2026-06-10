import CID
import Foundation

public enum CarParserError: Error {
    case dataTooSmall
    case invalidHeader(Error)
    case blockParseFailed(Error)
    case fileTreeReconstructionFailed(Error)
}

public enum CarParser {
    /// Parse a CARv1 archive from raw bytes into an unpacked file archive.
    ///
    /// Binary layout: `[header-varint | CBOR header] [block-varint | CID | data] ...`
    public static func parse(data: Data) throws -> UnpackedArchive {
        guard data.count >= 10 else {
            throw CarParserError.dataTooSmall
        }

        var offset = 0

        // 1. Read header
        let (headerLen, headerVarIntSize) = try data.readUVarInt(at: offset)
        offset += headerVarIntSize

        let headerEnd = offset + Int(headerLen)
        guard headerEnd <= data.count else {
            throw CarParserError.dataTooSmall
        }

        let headerBytes = data[data.startIndex + offset ..< data.startIndex + headerEnd]
        let header: CarHeader
        do {
            header = try CarHeaderDecoder.decode(from: Data(headerBytes))
        } catch {
            throw CarParserError.invalidHeader(error)
        }

        offset = headerEnd

        // 2. Parse blocks
        var blocks: [CID: BlockData] = [:]

        while offset < data.count {
            let (blockLen, blockVarIntSize) = try data.readUVarInt(at: offset)
            offset += blockVarIntSize

            let blockEnd = offset + Int(blockLen)
            guard blockEnd <= data.count else {
                throw CarParserError.dataTooSmall
            }

            // Parse CID at start of block
            let parsedCid: ParsedCid
            do {
                parsedCid = try CidParser.parseCid(from: data, at: offset)
            } catch {
                throw CarParserError.blockParseFailed(error)
            }

            // Remaining bytes after CID are block data
            let dataStart = offset + parsedCid.totalBytesRead
            let blockData = Data(data[data.startIndex + dataStart ..< data.startIndex + blockEnd])

            blocks[parsedCid.cid] = BlockData(data: blockData, codec: parsedCid.cid.codec)

            offset = blockEnd
        }

        // 3. Reconstruct file tree from root CID
        guard let rootCidBytes = header.roots.first else {
            throw CarParserError.invalidHeader(CarHeaderError.noRoots)
        }

        let rootCid: CID
        do {
            rootCid = try CidParser.parseCid(from: rootCidBytes, at: 0).cid
        } catch {
            throw CarParserError.blockParseFailed(error)
        }

        let fileTree: [String: Data]
        do {
            fileTree = try UnixFsDecoder.reconstructFileTree(rootCid: rootCid, blocks: blocks)
        } catch {
            throw CarParserError.fileTreeReconstructionFailed(error)
        }

        return UnpackedArchive(files: fileTree)
    }

    /// Heuristic check: does this data look like a CARv1 archive?
    /// Checks for valid varint + CBOR header with version 1.
    public static func looksLikeCarArchive(_ data: Data) -> Bool {
        guard data.count >= 10 else { return false }

        do {
            let (headerLen, headerVarIntSize) = try data.readUVarInt(at: 0)
            let headerEnd = headerVarIntSize + Int(headerLen)

            guard headerEnd <= data.count else { return false }

            let headerBytes = data[data.startIndex + headerVarIntSize ..< data.startIndex + headerEnd]
            let header = try CarHeaderDecoder.decode(from: Data(headerBytes))

            return header.version == 1 && !header.roots.isEmpty
        } catch {
            return false
        }
    }
}
