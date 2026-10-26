import Foundation
import Testing
@testable import MessageExchangeKit

struct ShortLivedStatementPriorityFactoryTests {
    @Test("Statements submitted within the same second get increasing sequence numbers")
    func sequenceIncreasesWithinOneSecond() {
        let provider = PeerSessionPriorityProvider(
            priorityFactory: ShortLivedStatementPriorityFactory(lifetimeInSeconds: 900),
            logger: nil
        )
        provider.expiry = provider.initialExpiry(from: [])

        let first = provider.incrementedExpiry()
        let second = provider.incrementedExpiry()

        #expect(second > first)
        #expect(second >> 32 >= first >> 32)
    }
}
