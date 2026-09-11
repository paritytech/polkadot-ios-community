import SubstrateSdk
import BigInt
import Foundation
import os
import Testing
@testable import Coinage

/// Records the delays the retry loop asked for instead of sleeping.
final class RecordingSleeper: @unchecked Sendable {
    private let delays = OSAllocatedUnfairLock(initialState: [TimeInterval]())

    var recorded: [TimeInterval] {
        delays.withLock { $0 }
    }

    func sleep(_ delay: TimeInterval) async throws {
        delays.withLock { $0.append(delay) }
        try Task.checkCancellation()
    }
}

/// Real `ExternalPaymentService` and state machine over an in-memory store and the stubbed lowest
/// seams: planner or spendable-assets provider, recycler, and a group-aware durability double.
struct ExternalPaymentHarness {
    let store: InMemoryExternalPaymentStore
    let txService: StubGroupTxService
    let recycler: StubCoinageRecyclingService
    let planner: StubExternalPaymentPlanner
    let assets: StubSpendableAssetsProvider
    let vouchers: StubVoucherService
    let sleeper: RecordingSleeper
    let service: ExternalPaymentService
}

enum ExternalPaymentTestFactory {
    static let denomination = DenominationBreakdownContext(
        unit: 1,
        precision: 0,
        maxExponent: 6,
        minExponent: 0
    )

    static let destination = Data(repeating: 7, count: 32)

    static func planks(_ exponent: Int16) -> Balance {
        denomination.valueInPlanks(for: exponent)
    }

    static func voucher(index: UInt64, exponent: Int16 = 3, readyAt: Date = .distantPast) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: Date(timeIntervalSince1970: 0),
            readyAt: readyAt,
            remoteState: .inRecycler(Voucher.Recycler(index: 1, membersCount: 8)),
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        )
    }

    static func coin(index: UInt64, exponent: Int16 = 3) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: index,
            age: 4,
            isOnchain: true,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        )
    }

    static func payment(
        origin: String = "getcash.dot",
        paymentId: String = "0xaa",
        amount: Balance = planks(3),
        spendScope: SpendScope = .spendable,
        round: Int = 0,
        settled: Balance = 0,
        stage: ExternalPayment.Stage = .plan,
        readyAt: Date = .distantPast,
        createdAt: Date = Date()
    ) -> ExternalPayment {
        ExternalPayment(
            origin: origin,
            paymentId: paymentId,
            amountInPlanks: amount,
            destination: destination,
            spendScope: spendScope,
            settledInPlanks: settled,
            round: round,
            stage: stage,
            readyAt: readyAt,
            createdAt: createdAt
        )
    }

    static func selection(
        vouchers: [Voucher] = [],
        coins: [Coin] = [],
        amount: Balance = planks(3),
        scope: SpendScope = .spendable
    ) -> ExternalPaymentPreview.Selection {
        ExternalPaymentPreview.Selection(vouchers: vouchers, coins: coins, fullAmount: amount, scope: scope)
    }

    static func makeStateFactory(
        planner: any ExternalPaymentPlanning,
        assets: any SpendableAssetsProviding = StubSpendableAssetsProvider(),
        recycler: StubCoinageRecyclingService = StubCoinageRecyclingService(),
        txService: StubGroupTxService = StubGroupTxService(),
        vouchers: [Voucher] = []
    ) -> ExternalPaymentStateFactory {
        ExternalPaymentStateFactory(
            instanceId: 0,
            planner: planner,
            spendableAssets: assets,
            context: denomination,
            recycler: recycler,
            voucherService: StubVoucherService(vouchers: vouchers),
            voucherKeyFactory: StubVoucherKeyFactory(),
            voucherMinter: StubVoucherMinter(),
            recyclerLoader: StubRecyclerReadinessLoader(),
            durability: txService,
            originFactory: StubOriginFactory(),
            quotaTracker: StubUnloadQuotaTracker(),
            blockNumberProvider: StubBlockInfoProvider(),
            logger: nil
        )
    }

    /// `usesRealPlanner` routes planning through the production planner over `assets`; otherwise
    /// the scripted stub planner answers.
    static func makeHarness(
        store: InMemoryExternalPaymentStore = InMemoryExternalPaymentStore(),
        usesRealPlanner: Bool = false,
        retryWindow: TimeInterval = 3_600
    ) -> ExternalPaymentHarness {
        let txService = StubGroupTxService()
        let recycler = StubCoinageRecyclingService()
        let stubPlanner = StubExternalPaymentPlanner()
        let assets = StubSpendableAssetsProvider()
        let vouchers = StubVoucherService()
        let sleeper = RecordingSleeper()
        let planner: any ExternalPaymentPlanning = usesRealPlanner
            ? ExternalPaymentPlanner(spendableAssets: assets)
            : stubPlanner

        let machineFactory = ExternalPaymentStateMachineFactory(
            instanceId: 0,
            planner: planner,
            spendableAssets: assets,
            recycler: recycler,
            voucherService: vouchers,
            voucherKeyFactory: StubVoucherKeyFactory(),
            voucherMinter: StubVoucherMinter(),
            recyclerLoader: StubRecyclerReadinessLoader(),
            extrinsicMonitor: StubExtrinsicMonitorFactory(),
            durability: txService,
            originFactory: StubOriginFactory(),
            quotaTracker: StubUnloadQuotaTracker(),
            blockNumberProvider: StubBlockInfoProvider(),
            logger: nil
        )

        let policy = ExternalPaymentRetryPolicy(
            window: retryWindow,
            backoff: 30,
            maxBackoff: 300,
            sleep: { try await sleeper.sleep($0) }
        )

        let service = ExternalPaymentService(
            store: store,
            planner: planner,
            stateMachineFactory: machineFactory,
            retryPolicy: policy,
            logger: nil
        )

        return ExternalPaymentHarness(
            store: store,
            txService: txService,
            recycler: recycler,
            planner: stubPlanner,
            assets: assets,
            vouchers: vouchers,
            sleeper: sleeper,
            service: service
        )
    }

    /// Polls until `condition` holds or `timeout` elapses; records an issue on timeout.
    @discardableResult
    static func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let satisfied = condition()
        if !satisfied {
            Issue.record("condition not met within \(timeout)s", sourceLocation: sourceLocation)
        }
        return satisfied
    }
}
