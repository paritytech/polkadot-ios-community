import Foundation
import SubstrateSdk

struct Web3SummitConfig {
    let dotNsUrl: URL
    let contractChainId: ChainModel.Id
    let contractAddress: Data
    let dryRunOrigin: AccountId
}

extension AppConfig {
    static func getWeb3Summit() throws -> Web3SummitConfig {
        let remote = AppConfigProvider.shared.getRemoteConfig()
        let dotNsUrl = remote!.web3SummitDotNsUrl!
        let contractHex = remote!.web3SummitContractAddress!

        return try Web3SummitConfig(
            dotNsUrl: dotNsUrl,
            contractChainId: AppConfig.Chains.assethubChain,
            contractAddress: contractHex.fromHex(),
            dryRunOrigin: reviveAccountId
        )
    }

    static let reviveAccountId: AccountId = {
        let data = Data("modlpy/reviv".utf8)
        return data + Data(repeating: 0, count: 32 - data.count)
    }()
}
