import Foundation
import JailbreakDetection

extension RootGate {
    struct Jailbreak: DecisionGate {
        private let detector: JailbreakDetector
        private let logger: LoggerProtocol

        init(detector: JailbreakDetector, logger: LoggerProtocol) {
            self.detector = detector
            self.logger = logger
        }

        func evaluate() -> RootDestination? {
            #if !DEBUG
                if detector.isJailbroken() {
                    logger.error("Jailbreak detected - blocking app execution")
                    return .jailbroken
                }
            #endif

            return nil
        }
    }
}
