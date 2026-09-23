import Foundation

@testable import polkadot_app

struct StubChatMessageOrderAllocator: ChatMessageOrderAllocating {
    let value: UInt64

    func nextOrder(after _: UInt64) -> UInt64 {
        value
    }
}
