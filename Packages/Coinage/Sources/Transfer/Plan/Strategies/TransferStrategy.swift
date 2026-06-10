import Foundation

/// Protocol for transfer execution strategies.
/// Each strategy encapsulates transaction building, signing, and submission.
protocol TransferStrategy {
    /// Executes the transfer strategy.
    /// Persists state changes via context after successful submission.
    /// - Parameter context: Context for persisting state changes after successful submission
    /// - Throws: If transaction building or submission fails
    func run(context: TransferContext) async throws
}
