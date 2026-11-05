import Foundation

enum DeviceTransferState: Equatable {
    case idle
    case waitingForSender
    case connecting
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
    case expired
    case rejected
    case cancelled
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
