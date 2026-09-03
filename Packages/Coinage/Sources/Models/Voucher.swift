import Foundation
import SubstrateSdk
import Operation_iOS

/// A coin currently residing in the Recycler, waiting for anonymity.
public struct Voucher: Equatable, CoinageDerivable {
    public let exponent: Int16 // 2^n
    public let derivationIndex: DerivationIndex
    public let allocatedAt: Date
    public let readyAt: Date
    public let remoteState: OnChainState
    public let privacy: VoucherPrivacyLevel

    /// On-chain public key (member key) derived from `derivationIndex`, cached so the durability
    /// layer never re-derives it on the fly.
    public let publicKey: PublicKey

    public var recycler: Recycler? { remoteState.recycler }

    public enum OnChainState: Equatable, Sendable {
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

    public struct Recycler: Equatable, Sendable {
        public let index: UInt32

        public init(index: UInt32) {
            self.index = index
        }
    }

    public init(
        exponent: Int16,
        derivationIndex: DerivationIndex,
        allocatedAt: Date,
        readyAt: Date,
        remoteState: OnChainState = .unlocated,
        privacy: VoucherPrivacyLevel = .degraded,
        publicKey: PublicKey
    ) {
        self.exponent = exponent
        self.derivationIndex = derivationIndex
        self.allocatedAt = allocatedAt
        self.readyAt = readyAt
        self.remoteState = remoteState
        self.privacy = privacy
        self.publicKey = publicKey
    }

    public func adjusting(state: OnChainState) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: allocatedAt,
            readyAt: readyAt,
            remoteState: state,
            privacy: privacy,
            publicKey: publicKey
        )
    }

    public func withReadinessState(_ state: VoucherPrivacyLevel) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: allocatedAt,
            readyAt: readyAt,
            remoteState: remoteState,
            privacy: state,
            publicKey: publicKey
        )
    }

    public func effectivePrivacy(at date: Date = .now) -> VoucherPrivacyLevel {
        privacy == .full && date >= readyAt ? .full : .degraded
    }

    public var isInRecycler: Bool {
        if case .inRecycler = remoteState { true } else { false }
    }

    /// Spendable without leaking its origin: in the recycler, past its unload delay, and drawn from
    /// a ring large enough to hide it. A missing half only lowers it to degraded, not unusable.
    public func isReadyToUseSecured(at date: Date = .now) -> Bool {
        isInRecycler && effectivePrivacy(at: date) == .full
    }
}

extension Voucher: Operation_iOS.Identifiable {
    public var identifier: String {
        Self.identifier(for: derivationIndex)
    }
}

public extension Voucher {
    /// The storage identifier for a voucher at `derivationIndex`. Single source of truth so no
    /// call site hand-writes the string form.
    static func identifier(for derivationIndex: DerivationIndex) -> String {
        "\(derivationIndex)"
    }
}
