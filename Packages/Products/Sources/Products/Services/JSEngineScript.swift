import Foundation

public struct JSEngineScript: Sendable {
    public enum InsertionPoint: Sendable {
        case atDocStart
        case atDocEnd
    }

    public let content: String
    public let insertionPoint: InsertionPoint

    public init(content: String, insertionPoint: InsertionPoint) {
        self.content = content
        self.insertionPoint = insertionPoint
    }
}
