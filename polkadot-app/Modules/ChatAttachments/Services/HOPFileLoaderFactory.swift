import Foundation
import SubstrateSdk
import HandoffService
import SDKLogger

enum HOPFileLoaderError: Error {
    case invalidUrl
    case noAvailableNodes
    case untrustedNode
}

protocol HOPFileLoaderMaking {
    func makeLoader(for node: ChatRemoteMessageContent.NodeEndpoint) throws -> HandoffFileLoading
}

final class HOPFileLoaderFactory {
    let logger: SDKLoggerProtocol

    init(logger: SDKLoggerProtocol) {
        self.logger = logger
    }
}

extension HOPFileLoaderFactory: HOPFileLoaderMaking {
    func makeLoader(for node: ChatRemoteMessageContent.NodeEndpoint) throws -> HandoffFileLoading {
        let url = try node.toURL()

        guard let connection = WebSocketEngine(
            urls: [url],
            connectionFactory: ConnectionTransportFactory(),
            logger: logger
        ) else {
            throw HOPFileLoaderError.noAvailableNodes
        }

        let service = HandoffService(connection: connection)
        return HandoffFileLoader(service: service)
    }
}

// MARK: - HOP Node Provider

protocol HOPNodeProviding {
    func selectNode() -> ChatRemoteMessageContent.NodeEndpoint?
    func isNodeAllowed(_ node: ChatRemoteMessageContent.NodeEndpoint) -> Bool
}

final class HOPNodeProvider {
    let chainRegistry: ChainRegistryProtocol
    let chainId: ChainModel.Id

    init(
        chainRegistry: ChainRegistryProtocol,
        chainId: ChainModel.Id = AppConfig.Chains.bulletInChain
    ) {
        self.chainRegistry = chainRegistry
        self.chainId = chainId
    }
}

extension HOPNodeProvider: HOPNodeProviding {
    func selectNode() -> ChatRemoteMessageContent.NodeEndpoint? {
        guard let api = hopApis()?.randomElement() else {
            return nil
        }

        return .wssUrl(api.url.absoluteString)
    }

    func isNodeAllowed(_ node: ChatRemoteMessageContent.NodeEndpoint) -> Bool {
        guard let url = try? node.toURL(),
              let apis = hopApis() else {
            return false
        }

        return apis.contains { $0.url == url }
    }
}

private extension HOPNodeProvider {
    func hopApis() -> Set<LocalChainExternalApi>? {
        chainRegistry.getChain(for: chainId)?.externalApis?.hop()
    }
}
