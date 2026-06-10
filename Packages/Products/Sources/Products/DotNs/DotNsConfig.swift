import Foundation

public struct DotNsConfig {
    public let contractsChainId: String
    public let resolverContractAddress: Data
    public let ipfsGatewayBaseUrl: URL

    public init(
        contractsChainId: String,
        resolverContractAddress: Data,
        ipfsGatewayBaseUrl: URL
    ) {
        self.contractsChainId = contractsChainId
        self.resolverContractAddress = resolverContractAddress
        self.ipfsGatewayBaseUrl = ipfsGatewayBaseUrl
    }
}
