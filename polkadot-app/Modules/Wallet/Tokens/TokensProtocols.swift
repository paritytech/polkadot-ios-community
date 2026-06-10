import Foundation

protocol TokensInputProtocol: AnyObject {
    func setup()
}

protocol TokensOutputProtocol: AnyObject {
    func didReceive(chainAssets: [ChainAsset])
    func didReceive(error: TokensFetchError)
}

enum TokensFetchError: Error {
    case fetchFailed(Error)
}
