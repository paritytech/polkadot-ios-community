import Foundation

enum DeviceTransferState: Equatable {
    case idle
    case waitingForSender
    case connecting
    case reconnecting
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

extension DeviceTransferState {
    /// Both coordinators move between states the same way; `nil` keeps the current one.
    func next(after event: DeviceTransferRunEvent) -> DeviceTransferState? {
        switch event {
        case .peerFound:
            self == .waitingForSender ? .connecting : nil
        case .channelOpened:
            self == .reconnecting ? .connecting : nil
        case .connectionLost:
            .reconnecting
        case let .progress(.syncing(applied, total)):
            .syncing(applied: applied, total: total)
        case let .progress(.files(progress)):
            .files(progress)
        }
    }
}

enum DeviceTransferFailure: Equatable {
    case expired
    case rejected
    case cancelled
    case aborted(DeviceTransferAbortReason)
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
        case let DeviceTransferRunError.aborted(reason):
            self = .aborted(reason)
        case is CancellationError:
            self = .cancelled
        default:
            self = .failed
        }
    }
}
