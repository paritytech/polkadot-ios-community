import Coinage
import Foundation
import Testing

@Suite("Payment Status")
struct PaymentStatusTests {
    // MARK: - Status Table

    @Test("Present at best head → Awaiting claim")
    func presentAtBestHeadAwaitingClaim() async throws {
        let status = try await paymentStatus(
            of: .coin(1),
            minter: .pending,
            presenceAtBest: .present(AssetPresence())
        )

        #expect(status == .awaitingClaim)
    }

    @Test("Absent + pending minter → Detecting")
    func absentPendingMinterDetecting() async throws {
        let status = try await paymentStatus(of: .coin(2), minter: .pending, presenceAtBest: .absent)

        #expect(status == .detecting)
    }

    @Test("Absent + pendingSuccess minter → Detecting")
    func absentPendingSuccessMinterDetecting() async throws {
        let status = try await paymentStatus(
            of: .coin(3),
            minter: .pendingSuccess,
            presenceAtBest: .absent
        )

        #expect(status == .detecting)
    }

    @Test("Absent + failure minter → Failed")
    func absentFailureMinterFailed() async throws {
        let status = try await paymentStatus(of: .coin(4), minter: .failure, presenceAtBest: .absent)

        #expect(status == .failed)
    }

    @Test("Absent + finalizedSuccess minter → Claimed")
    func absentFinalizedSuccessMinterClaimed() async throws {
        let status = try await paymentStatus(
            of: .coin(5),
            minter: .finalizedSuccess,
            presenceAtBest: .absent
        )

        #expect(status == .claimed)
    }

    @Test("Absent + no local minter → Detecting")
    func absentNoMinterDetecting() async throws {
        let status = try await paymentStatus(of: .coin(6), minter: nil, presenceAtBest: .absent)

        #expect(status == .detecting)
    }

    // MARK: - Failed Read Handling

    @Test("Failed read on presence → Detecting (never Failed or Claimed)")
    func failedReadOnPresenceDetecting() async throws {
        // Even though the minter is .failure, a failed read means absence is not proven,
        // so we cannot confidently say it failed — must return detecting.
        let status = try await paymentStatus(
            of: .coin(7),
            minter: .failure,
            presenceAtBest: .failedRead
        )

        #expect(status == .detecting)
    }

    @Test("Failed read with finalizedSuccess also → Detecting")
    func failedReadWithFinalizedSuccessDetecting() async throws {
        let status = try await paymentStatus(
            of: .coin(8),
            minter: .finalizedSuccess,
            presenceAtBest: .failedRead
        )

        #expect(status == .detecting)
    }

    // MARK: - Optimistic Handoff

    @Test("Optimistic handoff does not flip to Claimed while coin present at best")
    func handoffDoesNotFlipWhilePresent() async throws {
        // Even with a finalizedSuccess minter, presence at the best head takes precedence,
        // so the coin is awaiting claim rather than claimed.
        let status = try await paymentStatus(
            of: .coin(9),
            minter: .finalizedSuccess,
            presenceAtBest: .present(AssetPresence()),
            handedOff: true
        )

        #expect(status == .awaitingClaim)
    }
}

private extension PaymentStatusTests {
    /// Builds the whole world one query needs: a chain finalized at 150 with best head 160,
    /// a minter for `coin` at `minter` (none when nil), and the coin reading `presenceAtBest`
    /// at the best head.
    func paymentStatus(
        of coin: OwnAsset,
        minter minterStatus: EntryStatus?,
        presenceAtBest: ReadResult<AssetPresence>,
        handedOff: Bool = false
    ) async throws -> CoinPaymentStatus {
        let store = MockDurabilityStore()
        let chain = FakeChainView()
        let best = BlockRef.fixture(160)

        await chain.setChainView(finalized: .fixture(150), best: best)

        if let minterStatus {
            let minter = DurabilityEntry.fixture(outputs: [coin])
            try await store.register(minter)
            try await store.updateStatus(minter.id, to: minterStatus)
        }

        if handedOff {
            try await store.markHandedOff(coin)
        }

        await chain.setOutputPresence(at: best, to: [presenceAtBest])

        let query = PaymentStatusQuery(store: store, chain: chain)
        return try await query.status(of: coin, view: chain.pinChainView())
    }
}
