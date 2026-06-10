import Foundation

public enum StatementStoreAllowanceError: Error {
    case noSlotsAvailable(secsToWait: TimeInterval)
}
