import BigInt
import Foundation
import os
import SubstrateSdk
import Testing
@testable import Coinage

/// Real `ExternalPaymentService` and state machine over an in-memory store and the stubbed lowest
/// seams: scripted planner, scripted recycler, tracked coins/vouchers, and a group-aware durability
/// double.
struct ExternalPaymentHarness {
    let store: InMemoryExternalPaymentStore
    let txService: StubGroupTxService
    let recycler: StubCoinageRecyclingService
    let planner: StubExternalPaymentPlanner
    let coins: StubCoinService
    let vouchers: StubVoucherService
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
    static let freeState = CoinageAssetState(handedOff: false, consumerStatus: nil, minterStatus: nil)

    static func planks(_ exponent: Int16) -> Balance {
        denomination.valueInPlanks(for: exponent)
    }

    static func voucher(index: UInt64, exponent: Int16 = 3, inRecycler: Bool = true) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: Date(timeIntervalSince1970: 0),
            readyAt: .distantPast,
            remoteState: inRecycler ? .inRecycler(Voucher.Recycler(index: 1, membersCount: 8)) : .unlocated,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        )
    }

    static func tracked(_ voucher: Voucher, state: CoinageAssetState = freeState) -> TrackedVoucher {
        TrackedVoucher(voucher: voucher, state: state)
    }

    static func coin(index: UInt64, exponent: Int16 = 3, age: Int16? = 4, isOnchain: Bool = true) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: index,
            age: age,
            isOnchain: isOnchain,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        )
    }

    static func tracked(_ coin: Coin, state: CoinageAssetState = freeState) -> TrackedCoin {
        TrackedCoin(coin: coin, state: state)
    }

    static func payment(
        origin: String = "getcash.dot",
        paymentId: String = "0xaa",
        amount: Balance = planks(3),
        settled: Balance = 0,
        stage: ExternalPayment.Stage = .plan,
        createdAt: Date = Date()
    ) -> ExternalPayment {
        ExternalPayment(
            origin: origin,
            paymentId: paymentId,
            amountInPlanks: amount,
            destination: destination,
            settledInPlanks: settled,
            stage: stage,
            createdAt: createdAt
        )
    }

    static func selection(
        vouchers: [Voucher] = [],
        coins: [Coin] = [],
        amount: Balance = planks(3)
    ) -> ExternalPaymentPreview.Selection {
        ExternalPaymentPreview.Selection(vouchers: vouchers, coins: coins, fullAmount: amount)
    }

    static func recycleGroupId(for payment: ExternalPayment) -> CoinageTxGroupId {
        OnboardCoinsPaymentState.recyclingGroupId(for: payment)
    }

    static func unloadGroupId(for payment: ExternalPayment) -> CoinageTxGroupId {
        "external-payment:\(payment.id)"
    }

    static func makeStateFactory(
        planner: any ExternalPaymentPlanning,
        recycler: StubCoinageRecyclingService = StubCoinageRecyclingService(),
        txService: StubGroupTxService = StubGroupTxService(),
        vouchers: [Voucher] = []
    ) -> ExternalPaymentStateFactory {
        ExternalPaymentStateFactory(
            instanceId: 0,
            planner: planner,
            context: denomination,
            voucherService: StubVoucherService(vouchers: vouchers),
            recycler: recycler,
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

    static func makeHarness(
        store: InMemoryExternalPaymentStore = InMemoryExternalPaymentStore()
    ) -> ExternalPaymentHarness {
        let txService = StubGroupTxService()
        let recycler = StubCoinageRecyclingService()
        let planner = StubExternalPaymentPlanner()
        let coins = StubCoinService()
        let vouchers = StubVoucherService()

        let machineFactory = ExternalPaymentStateMachineFactory(
            instanceId: 0,
            planner: planner,
            voucherService: vouchers,
            recycler: recycler,
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

        let service = ExternalPaymentService(
            store: store,
            planner: planner,
            stateMachineFactory: machineFactory,
            logger: nil
        )

        return ExternalPaymentHarness(
            store: store,
            txService: txService,
            recycler: recycler,
            planner: planner,
            coins: coins,
            vouchers: vouchers,
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
