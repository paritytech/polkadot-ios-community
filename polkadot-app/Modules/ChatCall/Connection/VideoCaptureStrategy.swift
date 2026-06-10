import Foundation
import AVFoundation
import WebRTC

struct VideoCaptureParams {
    let format: AVCaptureDevice.Format
    let fps: Int
}

struct VideoCapturePreferences {
    let maxWidth: Int
    let maxHeight: Int
    let maxFps: Int

    static var defaultPreferences: VideoCapturePreferences {
        VideoCapturePreferences(maxWidth: 1_280, maxHeight: 720, maxFps: 30)
    }
}

protocol VideoCaptureStrategyProtocol {
    func deriveParams(for device: AVCaptureDevice) -> VideoCaptureParams?
}

///  The video capture strategy ensures that participants of the call uses preferred aspect scale ratio and max fps.
///  That allows stable connection by preventing encoder/decoder overloads on both sides. For example,
///  one device might send ultra high res video while the receiver is too slow to process it or event doesn't support
/// that
///  format.
final class VideoCaptureStrategy {
    let preferences: VideoCapturePreferences
    let logger: LoggerProtocol

    init(preferences: VideoCapturePreferences, logger: LoggerProtocol = Logger.shared) {
        self.preferences = preferences
        self.logger = logger
    }
}

private extension VideoCaptureStrategy {
    func fallbackWhenDimensionsNotMatch(for device: AVCaptureDevice) -> VideoCaptureParams? {
        let allFormats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = allFormats.first else {
            return nil
        }

        let maxFps = Double(preferences.maxFps)

        let fps = format.videoSupportedFrameRateRanges
            .filter { $0.maxFrameRate <= maxFps }
            .sorted { $0.maxFrameRate < $1.maxFrameRate }
            .last ?? format.videoSupportedFrameRateRanges.first

        guard let fps else {
            return nil
        }

        return VideoCaptureParams(format: format, fps: Int(fps.maxFrameRate))
    }
}

extension VideoCaptureStrategy: VideoCaptureStrategyProtocol {
    func deriveParams(for device: AVCaptureDevice) -> VideoCaptureParams? {
        let suitableFormats = RTCCameraVideoCapturer.supportedFormats(for: device)
            .filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width <= preferences.maxWidth && dimensions.height <= preferences.maxHeight
            }
            .sorted { form1, form2 -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(form1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(form2.formatDescription).width
                return width1 < width2
            }

        // Choose best format (highest resolution within constraints)
        guard let format = suitableFormats.last else {
            logger.warning("No format matching preferred dimensions. Using fallback")
            return fallbackWhenDimensionsNotMatch(for: device)
        }

        let maxFps = Double(preferences.maxFps)

        let fps = format.videoSupportedFrameRateRanges
            .filter { $0.maxFrameRate <= maxFps }
            .sorted { $0.maxFrameRate < $1.maxFrameRate }
            .last ?? format.videoSupportedFrameRateRanges.first

        guard let fps else {
            logger.error("No FPS range available")
            return nil
        }

        let targetFps = min(Int(fps.maxFrameRate), preferences.maxFps)

        return VideoCaptureParams(format: format, fps: targetFps)
    }
}
