import UIKit
import Products

@MainActor
protocol SPAControllerPooling: AnyObject {
    func controller(for id: UUID) -> SPAViewProtocol?
    func makeController(for tab: SPATab) -> SPAViewProtocol?
    func removeController(for id: UUID)
}

@MainActor
final class SPAControllerPool: SPAControllerPooling {
    private var controllers: [UUID: SPAViewProtocol] = [:]
    private var sharedFlowState: SPAFlowState?

    func controller(for id: UUID) -> SPAViewProtocol? { controllers[id] }

    func makeController(for tab: SPATab) -> SPAViewProtocol? {
        if let existing = controllers[tab.id] { return existing }
        guard let page = tab.makeProductPage() else { return nil }

        let flowState: SPAFlowState
        if let sharedFlowState {
            flowState = sharedFlowState
        } else {
            guard let created = SPAFlowState.create() else { return nil }
            sharedFlowState = created
            flowState = created
        }

        guard let view = SPAViewFactory.createView(
            page: page,
            flowState: flowState,
            isBrowserTab: true,
            browserTabId: tab.id
        ) else {
            return nil
        }
        controllers[tab.id] = view
        return view
    }

    func removeController(for id: UUID) { controllers[id] = nil }
}
