import Foundation
import Foundation_iOS
import WebRTC
import SubstrateSdk
import CoreImage // Added for SimulatedVideoCapturer
import os

protocol RTCRendererManaging: AnyObject {
    func connectLocalRenderer(_ renderer: RTCVideoRenderer)
    func disconnectLocalRenderer(_ renderer: RTCVideoRenderer)

    func hasRemoteVideoTrack(for peerId: AccountId) -> Bool
    func connectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId)
    func disconnectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId)
}

final class RTCClient {
    // The `RTCPeerConnectionFactory` is in charge of creating new RTCPeerConnection instances.
    // A new RTCPeerConnection should be created every new call, but the factory is shared.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()

    private var videoCapturer: RTCVideoCapturer?

    private struct MutableState {
        var remoteVideoTracks: [AccountId: RTCVideoTrack] = [:]
        var isLocalCaptureStarted = false
        var localVideoTrack: RTCVideoTrack?
    }

    private let state = OSAllocatedUnfairLock(initialState: MutableState())

    var localVideoTrack: RTCVideoTrack? {
        state.withLock { $0.localVideoTrack }
    }

    private let isAudioEnabled: Bool
    private let logger: LoggerProtocol
    private let rtcLogger: RTCCallbackLogger?

    init(
        isAudioEnabled: Bool,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.isAudioEnabled = isAudioEnabled
        self.logger = logger

        if EnviromentVariables.isDebugEnabled {
            rtcLogger = RTCCallbackLogger()
            startLogging()
        } else {
            rtcLogger = nil
        }

        createMediaSenders()
    }

    deinit {
        stopLogging()
    }

    // MARK: - Local Capture Lifecycle

    /// Starts the camera capture so the local video track produces frames.
    /// Peer connections can attach the local video track before capture starts.
    func startLocalCapture() {
        state.withLock { state in
            guard !state.isLocalCaptureStarted else { return }
            if performStartCapture() {
                state.isLocalCaptureStarted = true
            }
        }
    }

    func stopLocalCapture() {
        state.withLock { state in
            guard state.isLocalCaptureStarted else { return }
            performStopCapture()
            state.isLocalCaptureStarted = false
        }
    }

    // MARK: - Remote Track Management

    /// Sets the remote video track for a given peer. Called when connection state updates.
    func setRemoteVideoTrack(_ track: RTCVideoTrack?, for peerId: AccountId) {
        state.withLock { $0.remoteVideoTracks[peerId] = track }
    }

    /// Removes the remote video track for a given peer.
    func removeRemoteVideoTrack(for peerId: AccountId) {
        state.withLock { _ = $0.remoteVideoTracks.removeValue(forKey: peerId) }
    }

    /// Removes all remote video tracks.
    func removeAllRemoteVideoTracks() {
        state.withLock { $0.remoteVideoTracks.removeAll() }
    }

    // MARK: - Private

    private func createMediaSenders() {
        let track = createLocalVideoTrack()
        state.withLock { $0.localVideoTrack = track }
    }

    private func createLocalVideoTrack() -> RTCVideoTrack {
        let videoSource = RTCClient.factory.videoSource()

        #if targetEnvironment(simulator)
            // Use our custom simulated capturer
            videoCapturer = SimulatedVideoCapturer(delegate: videoSource)
        #else
            videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        #endif

        let videoTrack = RTCClient.factory.videoTrack(with: videoSource, trackId: "video0")
        return videoTrack
    }

    private func performStartCapture() -> Bool {
        #if targetEnvironment(simulator)
            guard let capturer = videoCapturer as? SimulatedVideoCapturer else {
                return false
            }
            capturer.startCapture()
            return true
        #else
            guard let capturer = videoCapturer as? RTCCameraVideoCapturer else {
                return false
            }
            guard
                let frontCamera = (RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front })),
                let format = RTCCameraVideoCapturer.supportedFormats(for: frontCamera).first(where: {
                    guard $0.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate <= 30 }) else {
                        return false
                    }
                    return CMVideoFormatDescriptionGetDimensions($0.formatDescription).height <= 720
                })
            else {
                return false
            }

            capturer.startCapture(
                with: frontCamera,
                format: format,
                fps: 24
            )
            return true
        #endif
    }

    private func performStopCapture() {
        #if targetEnvironment(simulator)
            if let capturer = videoCapturer as? SimulatedVideoCapturer {
                capturer.stopCapture()
            }
        #else
            if let capturer = videoCapturer as? RTCCameraVideoCapturer {
                capturer.stopCapture()
            }
        #endif
    }
}

// MARK: - RTCRendererManaging

extension RTCClient: RTCRendererManaging {
    func connectLocalRenderer(_ renderer: RTCVideoRenderer) {
        startLocalCapture()
        let track = state.withLock { $0.localVideoTrack }
        track?.add(renderer)
    }

    func disconnectLocalRenderer(_ renderer: RTCVideoRenderer) {
        let track = state.withLock { $0.localVideoTrack }
        track?.remove(renderer)
    }

    func hasRemoteVideoTrack(for peerId: AccountId) -> Bool {
        state.withLock { $0.remoteVideoTracks[peerId] != nil }
    }

    func connectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId) {
        let track = state.withLock { $0.remoteVideoTracks[peerId] }
        track?.add(renderer)
    }

    func disconnectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId) {
        let track = state.withLock { $0.remoteVideoTracks[peerId] }
        track?.remove(renderer)
    }
}

// MARK: - Logs

private extension RTCClient {
    func startLogging() {
        guard let rtcLogger else {
            return
        }

        rtcLogger.severity = .none
        rtcLogger.start { [weak self] message, severity in
            guard let self else {
                return
            }
            let message = "[WEBRTC] \(message)"
            switch severity {
            case .verbose:
                logger.verbose(message)
            case .info:
                logger.info(message)
            case .warning:
                logger.warning(message)
            case .error:
                // Log WebRTC error with our warning
                // level to have cleaner error logs
                logger.warning("[RTC Error]\(message)")
            case .none:
                break
            @unknown default:
                logger.verbose(message)
            }
        }
    }

    func stopLogging() {
        rtcLogger?.stop()
    }
}

// MARK: - Simulated Capturer

#if targetEnvironment(simulator)
    private class SimulatedVideoCapturer: RTCVideoCapturer {
        private let timerQueue = DispatchQueue(label: "SimulatedVideoCapturer")
        private var timer: DispatchSourceTimer?
        private var frameIndex = 0
        private let ciContext = CIContext()
        // Changed to Portrait aspect ratio (480x640)
        private let width: CGFloat = 480
        private let height: CGFloat = 640

        override init(delegate: RTCVideoCapturerDelegate) {
            super.init(delegate: delegate)
        }

        func startCapture(fps: Int = 30) {
            stopCapture() // ensure clean restart

            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now(), repeating: 1.0 / Double(fps))
            timer.setEventHandler { [weak self] in
                self?.sendFrame()
            }
            timer.resume()
            self.timer = timer
        }

        func stopCapture() {
            timer?.cancel()
            timer = nil
        }

        private func sendFrame() {
            frameIndex += 1

            // Render on main thread if using UIKit (UIGraphicsImageRenderer) or do pure CIContext off-main
            // For safety/ease with UIGraphicsImageRenderer, we'll sync to main.
            // In prod code you'd want CoreGraphics/CoreImage purely on background.
            var image: UIImage?
            DispatchQueue.main.sync {
                image = generateImage(frameIndex: frameIndex)
            }

            guard let image, let nv12Buffer = createNV12Buffer(from: image) else { return }

            let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: nv12Buffer)
            let timeStampNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
            let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: ._0, timeStampNs: timeStampNs)

            delegate?.capturer(self, didCapture: frame)
        }

        private func generateImage(frameIndex: Int) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1 // Force 1:1 scale (no Retina scaling)

            return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
                // Background
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                // Animated Circle: "Moving slightly from left to right"
                UIColor.systemTeal.setFill()

                let xOffset = sin(Double(frameIndex) * 0.1) * 50.0

                // Center calculation for 480 width: (480 - 300) / 2 = 90
                let circleBaseX = (width - 300) / 2
                let circleX = circleBaseX + xOffset

                // Center calculation for 640 height: (640 - 300) / 2 = 170
                let circleY = (height - 300) / 2

                ctx.cgContext.fillEllipse(in: CGRect(x: circleX, y: circleY, width: 300, height: 300))

                // Text
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
                let string = "SIMULATOR"
                let size = string.size(withAttributes: attrs)

                let textX = circleX + (300 - size.width) / 2.0
                let textY = circleY + (300 - size.height) / 2.0

                string.draw(
                    at: CGPoint(x: textX, y: textY),
                    withAttributes: attrs
                )
            }
        }

        private func createNV12Buffer(from image: UIImage) -> CVPixelBuffer? {
            guard let cgImage = image.cgImage else { return nil }

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: Int(width),
                kCVPixelBufferHeightKey as String: Int(height)
            ]

            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(width),
                Int(height),
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                attributes as CFDictionary,
                &buffer
            )

            guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }

            let ciImage = CIImage(cgImage: cgImage)
            ciContext.render(ciImage, to: pixelBuffer)

            return pixelBuffer
        }
    }
#endif
