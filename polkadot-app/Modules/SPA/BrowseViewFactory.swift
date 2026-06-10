import Foundation

enum BrowseViewFactory {
    @MainActor
    static func createBrowseRootView() -> SPAViewProtocol? {
        guard let flowState = SPAFlowState.create() else {
            return nil
        }

        return SPAViewFactory.createView(configuration: .browseRoot(), flowState: flowState)
    }
}
