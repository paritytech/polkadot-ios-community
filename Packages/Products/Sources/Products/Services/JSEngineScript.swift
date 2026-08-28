import Foundation

public struct JSEngineScript: Sendable {
    public enum InsertionPoint: Sendable {
        case atDocStart
        case atDocEnd
    }

    public enum FrameScope: Equatable, Sendable {
        case mainFrameOnly
        case allFrames
    }

    public let content: String
    public let insertionPoint: InsertionPoint
    public let frameScope: FrameScope

    public init(
        content: String,
        insertionPoint: InsertionPoint,
        frameScope: FrameScope = .mainFrameOnly
    ) {
        self.content = content
        self.insertionPoint = insertionPoint
        self.frameScope = frameScope
    }
}
