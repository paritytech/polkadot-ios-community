import Foundation
import PolkadotUI
import Products

@Observable
final class ProductWidgetViewModel: WidgetNodeProviding {
    @MainActor private(set) var node: CustomMessageWidgetNode?

    private let messageId: String
    private let runtime: ChatRuntimeProtocol
    private let tokenResolver: any WidgetDesignTokenResolving
    private let logger: LoggerProtocol
    private var renderTask: Task<Void, Never>?

    init(
        messageId: String,
        messageType: String,
        messageData: Data,
        runtime: ChatRuntimeProtocol,
        tokenResolver: any WidgetDesignTokenResolving,
        logger: LoggerProtocol
    ) {
        self.messageId = messageId
        self.runtime = runtime
        self.tokenResolver = tokenResolver
        self.logger = logger

        renderTask = Task { [weak self] in
            guard let self else { return }

            let stream = await runtime.renderMessage(
                messageId: messageId,
                messageType: messageType,
                messageData: messageData
            )

            do {
                for try await output in stream {
                    guard !Task.isCancelled else { return }

                    let resolved: CustomMessageWidgetNode? = switch output {
                    case let .scaleEncoded(hexString):
                        try ScaleWidget.decode(from: hexString)
                            .toWidgetNode(resolver: self.tokenResolver)
                    case let .native(node):
                        node.toWidgetNode(resolver: self.tokenResolver)
                    }
                    await MainActor.run { self.node = resolved }
                    Self.writeSimulatorRendererMarkerIfNeeded()
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Widget render stream failed for \(messageId): \(error)")
            }
        }
    }

    deinit {
        renderTask?.cancel()
    }

    #if IOS_PASEO_E2E && targetEnvironment(simulator)
        private static let e2eMarkersEnabled =
            ProcessInfo.processInfo.environment["TRUAPI_IOS_E2E_RUNTIME_MARKERS"] == "1"
    #endif

    /// Signals the truapi E2E launcher that a custom-rendered widget reached the UI.
    private static func writeSimulatorRendererMarkerIfNeeded() {
        #if IOS_PASEO_E2E && targetEnvironment(simulator)
            guard e2eMarkersEnabled else { return }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("truapi-e2e", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try Data().write(
                    to: directory.appendingPathComponent("custom-renderer-update"),
                    options: .atomic
                )
            } catch {
                // The E2E harness reports the missing marker.
            }
        #endif
    }
}
