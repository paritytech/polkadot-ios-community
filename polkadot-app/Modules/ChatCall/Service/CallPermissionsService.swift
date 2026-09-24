import AVFoundation
import UIKit

protocol CallPermissionsServicing: AnyObject {
    /// Only an explicit denial. A permission that has never been asked for is not a denial:
    /// iOS shows no Microphone switch in Settings until the app has asked at least once, so
    /// blocking on it would leave the user with nothing to turn on.
    var isMicrophoneDenied: Bool { get }

    func ensurePermissions(for callType: ChatCallType) async -> Bool
}

final class CallPermissionsService {
    private let applicationStateProvider: @MainActor () -> UIApplication.State

    init(
        applicationStateProvider: @escaping @MainActor () -> UIApplication.State = {
            UIApplication.shared.applicationState
        }
    ) {
        self.applicationStateProvider = applicationStateProvider
    }
}

private extension CallPermissionsService {
    // An inactive/backgrounded app (e.g. a locked-screen CallKit answer) can't
    // present the system permission prompt. Awaiting one there stalls the call
    // instead of surfacing a dialog, so only prompt when the app is active.
    @MainActor
    var canPresentPermissionPrompt: Bool {
        applicationStateProvider() == .active
    }

    func requestMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            guard await canPresentPermissionPrompt else { return false }
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    func requestCameraAccessIfNeeded(for callType: ChatCallType) async {
        guard
            callType == .video,
            AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined,
            await canPresentPermissionPrompt
        else {
            return
        }

        _ = await AVCaptureDevice.requestAccess(for: .video)
    }
}

extension CallPermissionsService: CallPermissionsServicing {
    var isMicrophoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    func ensurePermissions(for callType: ChatCallType) async -> Bool {
        guard await requestMicrophoneAccess() else {
            return false
        }

        // Camera denial is tolerated: the call degrades to audio-only,
        // so only the microphone is a hard requirement.
        await requestCameraAccessIfNeeded(for: callType)

        return true
    }
}
