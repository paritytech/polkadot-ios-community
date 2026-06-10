import Foundation

@MainActor
final class TopUpRequestWireframe: TopUpRequestWireframeProtocol {
    func dismiss(view: TopUpRequestViewProtocol?) {
        view?.controller.dismiss(animated: true)
    }
}
