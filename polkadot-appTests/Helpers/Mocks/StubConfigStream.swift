import AsyncExtensions
import Foundation

@testable import polkadot_app

final class StubConfigStream: RemoteConfigObserving {
    private let subject = AsyncCurrentValueSubject<RemoteAppConfig?>(nil)
    private(set) var subscriptionCount = 0

    func remoteConfigStream() -> AnyAsyncSequence<RemoteAppConfig> {
        subscriptionCount += 1
        return subject.compacted().eraseToAnyAsyncSequence()
    }

    func send(_ config: RemoteAppConfig) {
        subject.send(config)
    }
}
