@testable import polkadot_app

/// Records whether the screen may sleep after each change.
final class ScreenSleepSpy: OperatingSystemMediating, @unchecked Sendable {
    private let recorder = DeviceSyncTestEventRecorder<Bool>()

    /// `true` while the screen is kept on.
    var keptAwake: [Bool] { recorder.snapshot }

    func disableScreenSleep() {
        recorder.record(true)
    }

    func enableScreenSleep() {
        recorder.record(false)
    }
}
