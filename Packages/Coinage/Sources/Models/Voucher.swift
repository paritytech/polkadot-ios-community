import Foundation
import SubstrateSdk
import Operation_iOS

/// A coin currently residing in the Recycler, waiting for anonymity.
public struct Voucher: Equatable, CoinageDerivable {
    public let exponent: Int16 // 2^n
    public let derivationIndex: UInt32
    public let allocatedAt: Date
    public let readyAt: Date
    public let remoteState: OnChainState
    public var localState: State = .available
    public let privacy: VoucherPrivacyLevel

    public var recycler: Recycler? { remoteState.recycler }

    /// Local operational state of the voucher - independent of on-chain state.
    public enum State: Equatable {
        case available
        case pendingTransfer
        /// Surplus voucher allocated but not yet confirmed on-chain.
        case pendingOnboarding
    }

    public enum OnChainState: Equatable {
        case unlocated
        case onboarding
        case inRecycler(Recycler)

        var recycler: Recycler? {
            switch self {
            case let .inRecycler(recycler): recycler
            case .unlocated,
                 .onboarding: nil
            }
        }

        public var pending: Bool {
            switch self {
            case .unlocated,
                 .onboarding: true
            case .inRecycler: false
            }
        }
    }

    public struct Recycler: Equatable {
        public let index: UInt32

        public init(index: UInt32) {
            self.index = index
        }
    }

    public init(
        exponent: Int16,
        derivationIndex: UInt32,
        allocatedAt: Date,
        readyAt: Date,
        remoteState: OnChainState = .unlocated,
        localState: State = .available,
        privacy: VoucherPrivacyLevel = .degraded
    ) {
        self.exponent = exponent
        self.derivationIndex = derivationIndex
        self.allocatedAt = allocatedAt
        self.readyAt = readyAt
        self.remoteState = remoteState
        self.localState = localState
        self.privacy = privacy
    }

    public func adjusting(state: OnChainState) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: allocatedAt,
            readyAt: readyAt,
            remoteState: state,
            localState: localState,
            privacy: privacy
        )
    }

    public func withLocalState(_ localState: State) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: allocatedAt,
            readyAt: readyAt,
            remoteState: remoteState,
            localState: localState,
            privacy: privacy
        )
    }

    public func withReadinessState(_ state: VoucherPrivacyLevel) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: allocatedAt,
            readyAt: readyAt,
            remoteState: remoteState,
            localState: localState,
            privacy: state
        )
    }

    public func effectivePrivacy(at date: Date = .now) -> VoucherPrivacyLevel {
        privacy == .full && date >= readyAt ? .full : .degraded
    }
}

extension Voucher: Operation_iOS.Identifiable {
    public var identifier: String {
        "\(derivationIndex)"
    }
}
