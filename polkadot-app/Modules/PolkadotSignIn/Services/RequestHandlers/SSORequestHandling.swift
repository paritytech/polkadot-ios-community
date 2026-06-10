import Foundation

protocol SSORequestHandling {
    func canHandle(_ content: PolkadotHostRemoteMessage.LatestContent) -> Bool

    func handle(
        message: PolkadotHostRemoteMessage,
        from host: PolkadotSignInHost
    ) async
}
