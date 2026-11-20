import Testing
import Foundation
import Foundation_iOS
import Individuality
@testable import Coinage

/// Covers `VoucherLocationService.updates` — the join that attaches a ring's delivered unloaded count to
/// the in-recycler location, independent of capacity, and attaches fungibility only when both the count
/// and the denomination's capacity are known.
@Suite("VoucherLocationService.updates")
struct VoucherLocationUpdatesTests {
    private let enteredAt = Date(timeIntervalSince1970: 1_000)
    private let voucher = Voucher(
        exponent: 5,
        derivationIndex: 0,
        allocatedAt: Date(timeIntervalSince1970: 0),
        readyAt: Date(timeIntervalSince1970: 0),
        publicKey: Data(repeating: 0x71, count: 32)
    )

    struct UnloadedCountCase: Sendable {
        let delivered: UncertainStorage<UInt32?>?
        let expected: UInt32?
    }

    @Test(
        "The delivered unloaded count lands on the in-recycler location",
        arguments: [
            UnloadedCountCase(delivered: .defined(7), expected: 7),
            UnloadedCountCase(delivered: .defined(nil), expected: 0),
            UnloadedCountCase(delivered: .undefined, expected: nil),
            UnloadedCountCase(delivered: nil, expected: nil)
        ]
    )
    func unloadedCountIsWrittenOntoRecycler(_ testCase: UnloadedCountCase) throws {
        // Given
        let location = Voucher.OnChainState.inRecycler(.init(index: 5, membersCount: 3, enteredAt: enteredAt))
        let unloadedCounts: [CoinageKeyIndex: UncertainStorage<UInt32?>] = testCase.delivered.map { [0: $0] } ?? [:]

        // When
        let update = try #require(resolveUpdate(location: location, unloadedCounts: unloadedCounts))

        // Then
        let recycler = try #require(update.remoteState.recycler)
        #expect(recycler.unloadedCount == testCase.expected)
        #expect(recycler.index == 5)
        #expect(recycler.membersCount == 3)
        #expect(recycler.enteredAt == enteredAt)
    }

    @Test("A delivered count is carried even when ring capacity is unknown")
    func unloadedCountCarriedWithoutCapacity() throws {
        // Given
        let location = Voucher.OnChainState.inRecycler(.init(index: 5, membersCount: 3, enteredAt: enteredAt))

        // When
        let update = try #require(resolveUpdate(
            location: location,
            unloadedCounts: [0: .defined(3)],
            capacities: [:]
        ))

        // Then
        #expect(update.remoteState.recycler?.unloadedCount == 3)
        #expect(update.recyclerFungibility == nil)
        #expect(update.maxRecyclerFungibility == nil)
    }

    @Test("Fungibility is attached only with a delivered count and a known capacity")
    func fungibilityAttachedWithCountAndCapacity() throws {
        // Given
        let location = Voucher.OnChainState.inRecycler(.init(index: 5, membersCount: 3, enteredAt: enteredAt))

        // When
        let update = try #require(resolveUpdate(location: location, unloadedCounts: [0: .defined(2)]))

        // Then
        #expect(update.recyclerFungibility != nil)
        #expect(update.maxRecyclerFungibility != nil)
    }

    @Test("A non-recycler location passes through with no scores even when a count is delivered")
    func onboardingPassesThroughWithoutScores() throws {
        // Given
        let location = Voucher.OnChainState.onboarding

        // When
        let update = try #require(resolveUpdate(location: location, unloadedCounts: [0: .defined(2)]))

        // Then
        #expect(update.remoteState == .onboarding)
        #expect(update.recyclerFungibility == nil)
        #expect(update.maxRecyclerFungibility == nil)
    }
}

// MARK: - Helpers

private extension VoucherLocationUpdatesTests {
    func resolveUpdate(
        location: Voucher.OnChainState,
        unloadedCounts: [CoinageKeyIndex: UncertainStorage<UInt32?>] = [:],
        capacities: [Int16: Int] = [5: 10]
    ) -> VoucherLocationUpdate? {
        VoucherLocationService.updates(
            locations: [0: location],
            unloadedCounts: unloadedCounts,
            voucherByIndex: [0: voucher],
            capacities: capacities
        )[0]
    }
}
