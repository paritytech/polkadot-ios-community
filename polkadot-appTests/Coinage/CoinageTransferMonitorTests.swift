import Coinage
import Foundation
import StructuredConcurrencyTestSupport
import SubstrateSdk
import Testing
@testable import polkadot_app

/// The monitor, the store and the chat snapshot together: a scripted claim must reach the message as
/// one emission per distinct state, a terminal row must keep the monitor away for good, and a runtime
/// failure must leave the row exactly as the durability layer last reported it.
@Suite("Coinage transfer monitor", .serialized)
struct CoinageTransferMonitorTests {
    private let context = DenominationBreakdownContext(unit: 1_000, precision: 3, maxExponent: 10, minExponent: 0)

    @Test("an incoming claim reaches the message once per distinct state")
    func incomingClaimReachesMessage() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.incoming, totalValue: 10)
        let claims = MockClaimCoinsService(detections: [
            .detecting, .detecting, .claiming, .claimingRest(claimed: 4),
            .claimed(amount: 10, finalized: false), .claimed(amount: 10, finalized: true)
        ])
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(world: world, claims: claims)
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await states.collect { $0 == .incoming(.init(status: .claimed, actualValue: 10)) }
        let distinct = seen.enumerated().filter { $0.offset == 0 || seen[$0.offset - 1] != $0.element }.map(\.element)

        #expect(distinct == [
            nil,
            .incoming(.init(status: .detecting)),
            .incoming(.init(status: .claiming)),
            .incoming(.init(status: .claimed, actualValue: 10))
        ])
        #expect(seen.count == distinct.count, "every emission must carry a change")
        #expect(claims.calls.count == 1)
        #expect(claims.calls.first?.groupId == message.messageId)
    }

    @Test("a terminal row keeps the message out of the monitor on the next launch")
    func terminalRowIsNeverReprocessed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.incoming)
        try await world.store.updateIncoming(
            messageId: message.messageId,
            state: .init(status: .claimed, actualValue: 10)
        )
        let claims = MockClaimCoinsService(detections: [.claimed(amount: 10, finalized: true)])

        let monitor = makeMonitor(world: world, claims: claims)
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let candidates = world.messageProviderFactory.subscribeMessages(with: .incomingCoinageSendMessages())
        for try await messages in candidates {
            #expect(messages.isEmpty)
            break
        }
        #expect(claims.calls.isEmpty)
    }

    /// The failure log is the last statement of the monitor's catch, so once it has been written the
    /// task can no longer touch the row: what the row holds then is what it will hold.
    @Test("a runtime failure leaves the last durability-reported state in place")
    func runtimeFailureDoesNotWriteStatus() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.incoming)
        let claims = MockClaimCoinsService(detections: [.claiming], failure: MonitorTestError.chainUnavailable)
        let logger = MockLogger()

        let monitor = makeMonitor(world: world, claims: claims, logger: logger)
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        try await logger.waitForError(containing: "Failed to claim coinage for \(message.messageId)")

        let transfer = try #require(try await world.transfer(message.messageId))
        #expect(transfer.state == .incoming(.init(status: .claiming)))
    }

    @Test("an outgoing transfer follows the peer's claims to the claimed amount")
    func outgoingFollowsPeerClaims() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let coin = try makeCoin(exponent: 2)
        let statuses = MockCoinageTransferStatusService(snapshots: [
            [:],
            [coin.publicKey: CoinageTransferState(coin: coin, status: .awaitingClaim)],
            [coin.publicKey: CoinageTransferState(coin: coin, status: .awaitingClaim)],
            [coin.publicKey: CoinageTransferState(coin: coin, status: .claimed(finalized: true))]
        ])
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(
            world: world,
            statuses: statuses,
            timing: monitorTiming(for: message, elapsed: insideWindow)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let claimedValue = context.valueInPlanks(for: 2)
        let seen = try await states.collect { $0 == .outgoing(.init(status: .claimed, actualValue: claimedValue)) }
        let distinct = seen.enumerated().filter { $0.offset == 0 || seen[$0.offset - 1] != $0.element }.map(\.element)

        #expect(distinct == [
            nil,
            .outgoing(.init(status: .sending)),
            .outgoing(.init(status: .sent)),
            .outgoing(.init(status: .claimed, actualValue: claimedValue))
        ])
        #expect(seen.count == distinct.count, "every emission must carry a change")
        #expect(statuses.subscriptions.count == 1)
    }

    @Test("a payment still awaiting its claim after six hours from its send time is unclaimed")
    func awaitingAfterWindowIsUnclaimed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let statuses = try awaitingStatuses()
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(
            world: world,
            statuses: statuses,
            timing: monitorTiming(for: message, elapsed: CoinageConstants.claimWindow + 1)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await states.collect { $0 == .outgoing(.init(status: .unclaimed)) }

        #expect(seen.last == .outgoing(.init(status: .unclaimed)))
        #expect(!seen.contains(.outgoing(.init(status: .sent))))
    }

    @Test("a payment still awaiting its claim inside the window stays sent")
    func awaitingInsideWindowStaysSent() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let statuses = try awaitingStatuses()
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(
            world: world,
            statuses: statuses,
            timing: monitorTiming(for: message, elapsed: insideWindow)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await states.collect { $0 == .outgoing(.init(status: .sent)) }

        #expect(seen.last == .outgoing(.init(status: .sent)))
        #expect(!seen.contains(.outgoing(.init(status: .unclaimed))))
    }

    @Test("a payment that is still awaiting its claim flips to unclaimed when the window closes")
    func windowClosingFlipsSentToUnclaimed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let statuses = try awaitingStatuses()
        let clock = ManualClock()
        let dateProvider = MockDateProvider(
            now: Date.fromChatTimestamp(message.timestamp).addingTimeInterval(insideWindow)
        )

        let monitor = makeMonitor(
            world: world,
            statuses: statuses,
            timing: CoinageTransferMonitor.Timing(clock: clock, dateProvider: dateProvider)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        _ = try await world.stateStream(of: message.messageId)
            .collect { $0 == .outgoing(.init(status: .sent)) }
        await dateProvider.advance(by: CoinageConstants.claimWindow - insideWindow)
        await clock.resumeSleep(for: .seconds(CoinageConstants.claimWindow - insideWindow))

        let seen = try await world.stateStream(of: message.messageId)
            .collect { $0 == .outgoing(.init(status: .unclaimed)) }
        #expect(seen.last == .outgoing(.init(status: .unclaimed)))
    }

    @Test("a late claim still lands after an absent pass")
    func lateClaimAfterAbsentIsClaimed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.incoming, totalValue: 10)
        let claims = MockClaimCoinsService(detections: [.absent, .claimed(amount: 10, finalized: true)])
        let claimed = IncomingTransferState(status: .claimed, actualValue: 10)

        let monitor = makeMonitor(world: world, claims: claims)
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await world.stateStream(of: message.messageId).collect { $0 == .incoming(claimed) }
        #expect(seen.last == .incoming(claimed))
    }

    @Test("a claim that gave up is returned to the sender, never failed")
    func notClaimedIsReturned() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.incoming, totalValue: 10)
        let claims = MockClaimCoinsService(detections: [.notClaimed])
        let returned = IncomingTransferState(status: .returnedToSender)

        let monitor = makeMonitor(world: world, claims: claims)
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await world.stateStream(of: message.messageId).collect { $0 == .incoming(returned) }
        #expect(seen.last == .incoming(returned))
    }

    @Test("a detecting row re-enters the incoming candidates while a returned one does not")
    func detectingRowIsReprocessedReturnedIsNot() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let detecting = try await world.saveTransfer(.incoming)
        try await world.store.updateIncoming(
            messageId: detecting.messageId,
            state: .init(status: .detecting)
        )
        let returned = try await world.saveTransfer(.incoming)
        try await world.store.updateIncoming(
            messageId: returned.messageId,
            state: .init(status: .returnedToSender)
        )

        let candidates = world.messageProviderFactory.subscribeMessages(with: .incomingCoinageSendMessages())
        for try await messages in candidates {
            #expect(messages.map(\.messageId) == [detecting.messageId])
            break
        }
    }

    @Test("an unclaimed row stays in the outgoing candidates on the next launch")
    func unclaimedRowIsReprocessed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing)
        try await world.store.updateOutgoing(messageId: message.messageId, state: .init(status: .unclaimed))

        let candidates = world.messageProviderFactory.subscribeMessages(with: .outgoingLocalDeviceCoinageSendMessages())
        for try await messages in candidates {
            #expect(messages.map(\.messageId) == [message.messageId])
            break
        }
    }

    @Test("a final reclaim settles the payment as reclaimed with the reclaimed value")
    func finalReclaimSettlesReclaimed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let coin = try makeCoin(exponent: 2)
        let statuses = MockCoinageTransferStatusService(snapshots: [
            [coin.publicKey: CoinageTransferState(coin: coin, status: .reclaiming)],
            [coin.publicKey: CoinageTransferState(coin: coin, status: .reclaimed(finalized: true))]
        ])
        let reclaimed = OutgoingTransferState(status: .reclaimed, actualValue: context.valueInPlanks(for: 2))
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(
            world: world,
            statuses: statuses,
            timing: monitorTiming(for: message, elapsed: insideWindow)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await states.collect { $0 == .outgoing(reclaimed) }
        #expect(seen.last == .outgoing(reclaimed))
    }

    @Test("a reclaim that is not final yet writes reclaiming, never reclaimed")
    func nonFinalReclaimWritesReclaiming() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let coin = try makeCoin(exponent: 2)
        let statuses = MockCoinageTransferStatusService(snapshots: [
            [coin.publicKey: CoinageTransferState(coin: coin, status: .reclaimed(finalized: false))]
        ])
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(
            world: world,
            statuses: statuses,
            timing: monitorTiming(for: message, elapsed: insideWindow)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let reclaiming = OutgoingTransferState(status: .reclaiming)
        let seen = try await states.collect { $0 == .outgoing(reclaiming) }
        #expect(seen.last == .outgoing(reclaiming))
        #expect(!seen.contains(.outgoing(.init(status: .reclaimed, actualValue: context.valueInPlanks(for: 2)))))
    }

    @Test("a failed reclaim of an unclaimed coin writes reclaimFailed once the window has closed")
    func failedReclaimWritesReclaimFailed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let statuses = try awaitingStatuses()
        let reclaims = try MockReclaimCoinsService(failedReclaims: [[makeCoin(exponent: 2).publicKey]])
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(
            world: world,
            reclaims: reclaims,
            statuses: statuses,
            timing: monitorTiming(for: message, elapsed: CoinageConstants.claimWindow + 1)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await states.collect { $0 == .outgoing(.init(status: .reclaimFailed)) }
        #expect(seen.last == .outgoing(.init(status: .reclaimFailed)))
    }

    @Test("a retry that clears the failure returns the unclaimed payment to unclaimed")
    func retryClearingFailureIsUnclaimed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        let statuses = try awaitingStatuses()
        let reclaims = try MockReclaimCoinsService(failedReclaims: [[makeCoin(exponent: 2).publicKey], []])
        let states = world.stateStream(of: message.messageId)

        let monitor = makeMonitor(
            world: world,
            reclaims: reclaims,
            statuses: statuses,
            timing: monitorTiming(for: message, elapsed: CoinageConstants.claimWindow + 1)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        let seen = try await states.collect { $0 == .outgoing(.init(status: .unclaimed)) }
        #expect(seen.last == .outgoing(.init(status: .unclaimed)))
    }

    @Test("a relaunched reclaim-failed row never flickers to unclaimed before its failed reclaim is read")
    func relaunchedReclaimFailedNeverFlickersToUnclaimed() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let message = try await world.saveTransfer(.outgoing, totalValue: 10)
        try await world.store.updateOutgoing(messageId: message.messageId, state: .init(status: .reclaimFailed))
        let coin = try makeCoin(exponent: 2)
        let statuses = try awaitingStatuses()
        let reclaims = MockReclaimCoinsService(failedReclaims: [[coin.publicKey]])
        let recorder = RecordingTransferStateStore(base: world.store)

        let monitor = makeMonitor(
            world: world,
            reclaims: reclaims,
            statuses: statuses,
            store: recorder,
            timing: monitorTiming(for: message, elapsed: CoinageConstants.claimWindow + 1)
        )
        await monitor.setup()
        defer { Task { await monitor.throttle() } }

        var written: [OutgoingTransferState] = []
        for await state in recorder.outgoingWrites {
            written.append(state)
            if state.status == .reclaimFailed { break }
        }
        #expect(!written.map(\.status).contains(.unclaimed))
    }

    @Test("reclaiming and reclaim-failed rows re-enter the outgoing candidates while a reclaimed one does not")
    func reclaimRowsReEnterCandidates() async throws {
        let world = TransferStateTestWorld()
        try await world.setup()
        let reclaiming = try await world.saveTransfer(.outgoing)
        try await world.store.updateOutgoing(messageId: reclaiming.messageId, state: .init(status: .reclaiming))
        let failed = try await world.saveTransfer(.outgoing)
        try await world.store.updateOutgoing(messageId: failed.messageId, state: .init(status: .reclaimFailed))
        let finished = try await world.saveTransfer(.outgoing)
        try await world.store.updateOutgoing(
            messageId: finished.messageId,
            state: .init(status: .reclaimed, actualValue: 4)
        )

        let candidates = world.messageProviderFactory.subscribeMessages(with: .outgoingLocalDeviceCoinageSendMessages())
        for try await messages in candidates {
            #expect(Set(messages.map(\.messageId)) == [reclaiming.messageId, failed.messageId])
            break
        }
    }
}

private extension CoinageTransferMonitorTests {
    /// Half the window: inside it whatever the window's length (one minute in debug, six hours in release).
    var insideWindow: TimeInterval { CoinageConstants.claimWindow / 2 }

    func makeMonitor(
        world: TransferStateTestWorld,
        claims: MockClaimCoinsService = MockClaimCoinsService(detections: []),
        reclaims: MockReclaimCoinsService = MockReclaimCoinsService(),
        statuses: MockCoinageTransferStatusService = MockCoinageTransferStatusService(snapshots: []),
        store: (any TransferStateStoring)? = nil,
        timing: CoinageTransferMonitor.Timing = .live,
        logger: MockLogger = MockLogger()
    ) -> CoinageTransferMonitor {
        CoinageTransferMonitor(
            claimCoinsService: claims,
            reclaimCoinsService: reclaims,
            transferStatusService: statuses,
            denominationContext: { [context] in context },
            transferStateStore: store ?? world.store,
            storageFacade: world.facade,
            operationQueue: OperationQueue(),
            timing: timing,
            logger: logger
        )
    }

    /// The window is anchored to the message's send timestamp, so the provider's clock is placed relative to it.
    func monitorTiming(for message: Chat.LocalMessage, elapsed: TimeInterval) -> CoinageTransferMonitor.Timing {
        let sentAt = Date.fromChatTimestamp(message.timestamp)
        return CoinageTransferMonitor.Timing(
            clock: ManualClock(),
            dateProvider: MockDateProvider(now: sentAt.addingTimeInterval(elapsed))
        )
    }

    func awaitingStatuses() throws -> MockCoinageTransferStatusService {
        let coin = try makeCoin(exponent: 2)
        return MockCoinageTransferStatusService(snapshots: [
            [coin.publicKey: CoinageTransferState(coin: coin, status: .awaitingClaim)]
        ])
    }

    func makeCoin(exponent: Int16) throws -> Coin {
        let installation = try CoinageInstallationId(value: Data(repeating: 0x01, count: 32))
        return Coin(
            exponent: exponent,
            derivationIndex: CoinageKeyIndex(installation: installation, item: 0),
            age: 0,
            publicKey: Data(repeating: 0x09, count: 32)
        )
    }
}

private enum MonitorTestError: Error {
    case chainUnavailable
}
