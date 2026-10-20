@testable import polkadot_app
import Foundation

actor MockDeviceSyncFileLocator: DeviceSyncFileLocating {
    typealias FileReference = Chat.DeviceSyncFileMessage.FileReference

    nonisolated let locateEvents = DeviceSyncTestEventRecorder<FileReference>()

    private let locations: [FileReference: DeviceSyncFileLocation]
    private let gatedFile: FileReference?
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation

    init(locations: [FileReference: DeviceSyncFileLocation], gatedFile: FileReference? = nil) {
        self.locations = locations
        self.gatedFile = gatedFile
        (gate, gateContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func locate(_ file: FileReference) async -> DeviceSyncFileLocation {
        locateEvents.record(file)

        if file == gatedFile {
            for await _ in gate {
                break
            }
        }

        return locations[file] ?? .unavailable(.notStored)
    }

    nonisolated func openGate() {
        gateContinuation.yield(())
        gateContinuation.finish()
    }
}
