import Foundation
import Products
import SubstrateSdk
import KeyDerivation

protocol PolkadotSigningContextProtocol: AnyObject {
    var requester: PolkadotSigningRequester { get }
    var signingModel: PolkadotHostSigningModel { get }

    func resolveWallet(for account: ProductAccountId) throws -> WalletManaging
    func sendResult(_ result: PolkadotHostSigningResult) async throws
    func rejectRequest() async throws
}
