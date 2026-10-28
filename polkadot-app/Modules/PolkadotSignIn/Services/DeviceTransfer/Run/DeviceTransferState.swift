import Foundation

enum DeviceTransferState: Equatable {
    case idle
    /// The new phone published its request and waits for the old one to confirm it.
    case waitingForSender
    case connecting
    /// The old phone streams its data; it doesn't count progress itself.
    case transferring
    case syncing(applied: Int, total: Int)
    case files(DeviceTransferFileProgress)
    case finalizing
    case completed
    case failed(DeviceTransferFailure)

    var isRunning: Bool {
        switch self {
        case .idle,
             .completed,
             .failed: false
        default: true
        }
    }
}

enum DeviceTransferFailure: Equatable {
    /// The request outlived its 15 minutes before it was confirmed.
    case expired
    case rejected
    case cancelled
    /// The other phone cancelled.
    case aborted
    case timedOut
    case failed
}

extension DeviceTransferFailure {
    init(_ error: Error) {
        switch error {
        case DeviceTransferContextError.rejected:
            self = .rejected
        case DeviceTransferContextError.idleTimeout,
             DeviceTransferRunError.timedOut:
            self = .timedOut
        case DeviceTransferRunError.aborted:
            self = .aborted
        case is CancellationError:
            self = .cancelled
        default:
            self = .failed
        }
    }
}
