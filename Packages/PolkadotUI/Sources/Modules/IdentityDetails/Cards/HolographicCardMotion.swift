import CoreMotion
import SwiftUI

// Shared gyroscope source for the holographic-card effect. A single
// `CMMotionManager` is used (Apple advises one per app) and ref-counted across
// every `.holographicShader` in use. Tilt is normalised to -1...1, relative to a
// reference captured after a short warmup so neutral locks onto the user's hold.
// `delayedTilt` is a lagged copy used by trailing layers (e.g. a wordmark).

@MainActor
@Observable
final class HolographicCardMotion {
    static let shared = HolographicCardMotion()

    private(set) var tilt: CGPoint = .zero
    private(set) var delayedTilt: CGPoint = .zero

    private let manager = CMMotionManager()
    private var reference: CMAcceleration?
    private var warmupFrames = 0
    private var clients = 0

    private let warmupThreshold = 15
    private let sensitivity = 0.30
    private let smoothing = 0.55 // larger = snappier
    private let delaySmoothing = 0.10 // smaller = wordmark trails further

    private init() {}

    func retain() {
        clients += 1
        if clients == 1 { startUpdates() }
    }

    func release() {
        clients = max(0, clients - 1)
        if clients == 0 { stopUpdates() }
    }

    private func startUpdates() {
        guard manager.isDeviceMotionAvailable else { return }
        reference = nil
        warmupFrames = 0
        tilt = .zero
        delayedTilt = .zero
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.apply(motion.gravity)
            }
        }
    }

    private func stopUpdates() {
        manager.stopDeviceMotionUpdates()
    }

    private func apply(_ gravity: CMAcceleration) {
        guard let reference else {
            warmupFrames += 1
            if warmupFrames >= warmupThreshold { reference = gravity }
            return
        }

        let targetX = max(-1, min(1, (gravity.x - reference.x) / sensitivity))
        let targetY = max(-1, min(1, (reference.y - gravity.y) / sensitivity))

        tilt.x += (targetX - tilt.x) * smoothing
        tilt.y += (targetY - tilt.y) * smoothing

        delayedTilt.x += (tilt.x - delayedTilt.x) * delaySmoothing
        delayedTilt.y += (tilt.y - delayedTilt.y) * delaySmoothing
    }
}
