import Coinage
import UIKit
import UIKitExt

@MainActor
protocol TopUpRequestRouting: AnyObject {
    func showTopUpRequest(context: TopUpRequestContext, coinageService: any CoinageServicing)
}

@MainActor
final class TopUpRequestRouter: TopUpRequestRouting {
    private weak var presentationView: ControllerBackedProtocol?

    nonisolated init() {}

    func setPresentationView(_ view: ControllerBackedProtocol) {
        presentationView = view
    }

    func showTopUpRequest(context: TopUpRequestContext, coinageService: any CoinageServicing) {
        guard let view = TopUpRequestViewFactory.createView(
            context: context,
            coinageService: coinageService
        ) else {
            // Resolve the bridge continuation so JS doesn't hang if presentation fails.
            context.deliverFailed(TopUpRequestRouterError.presentationFailed)
            return
        }

        presentationView?.controller.present(view.controller, animated: true)
    }
}

enum TopUpRequestRouterError: Error, LocalizedError {
    case presentationFailed

    var errorDescription: String? {
        switch self {
        case .presentationFailed:
            "Failed to present the top-up sheet"
        }
    }
}
