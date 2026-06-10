import Foundation
import Products

protocol SPAScriptsMaking {
    func makeScripts() throws -> [JSEngineScript]
}

final class SPAScriptsFactory: SPAScriptsMaking {
    private let containerScriptProvider: ContainerScriptProviding

    init(containerScriptProvider: ContainerScriptProviding) {
        self.containerScriptProvider = containerScriptProvider
    }

    func makeScripts() throws -> [JSEngineScript] {
        let containerScript = try JSEngineScript(
            content: containerScriptProvider.loadContainerScript(),
            insertionPoint: .atDocStart
        )

        let disableZoomScript = JSEngineScript(
            content: """
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            document.head.appendChild(meta);
            """,
            insertionPoint: .atDocEnd
        )

        return [containerScript, disableZoomScript]
    }
}
