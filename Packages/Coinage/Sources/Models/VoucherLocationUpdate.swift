import Operation_iOS

/// The on-chain location and readiness a location sync resolves for a voucher — its `remoteState`
/// (onboarding / in-recycler) and `privacy` (degraded / full) — keyed by derivation index.
/// Persisted through a dedicated write-only mapper so a location write only ever touches these
/// fields, never reading-then-overwriting the rest of the voucher.
public struct VoucherLocationUpdate: Equatable, Sendable {
    public let derivationIndex: DerivationIndex
    public let remoteState: Voucher.OnChainState
    public let privacy: VoucherPrivacyLevel

    public init(
        derivationIndex: DerivationIndex,
        remoteState: Voucher.OnChainState,
        privacy: VoucherPrivacyLevel
    ) {
        self.derivationIndex = derivationIndex
        self.remoteState = remoteState
        self.privacy = privacy
    }
}

extension VoucherLocationUpdate: Operation_iOS.Identifiable {
    public var identifier: String { Voucher.identifier(for: derivationIndex) }
}
