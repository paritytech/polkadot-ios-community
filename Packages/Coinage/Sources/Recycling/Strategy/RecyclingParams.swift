import Foundation
import SubstrateSdk
import BigInt

/// Preset parameters for coin recycling and voucher readiness.
public struct RecyclingParams: Equatable {
    /// Share of total balance acceptable to hold *unavailable* while recycling. A ceiling, not a
    /// target — it exists so more than one coin can recycle at once.
    public let maxUnavailableBalance: BigRational

    /// Age below which recycling is not considered at all.
    public let minRecyclingAge: Int16

    /// Readiness rules for vouchers already included in a recycler ring.
    public let voucherReadiness: VoucherReadiness

    /// Whether gaining-privacy balance may be spent behind a confirmation.
    public let allowsConfirmedSpend: Bool

    public init(
        maxUnavailableBalance: BigRational,
        minRecyclingAge: Int16,
        voucherReadiness: VoucherReadiness,
        allowsConfirmedSpend: Bool
    ) {
        self.maxUnavailableBalance = maxUnavailableBalance
        self.minRecyclingAge = minRecyclingAge
        self.voucherReadiness = voucherReadiness
        self.allowsConfirmedSpend = allowsConfirmedSpend
    }
}

/// A voucher is ready when either the ring fill or the member-and-age requirements are satisfied.
public struct VoucherReadiness: Equatable {
    /// Ring fill required for immediate readiness.
    public let requiredRingFill: BigRational
    /// Nil means readiness depends on ring fill alone.
    public let memberAndAgeRequirements: MemberAndAgeRequirements?

    public init(requiredRingFill: BigRational, memberAndAgeRequirements: MemberAndAgeRequirements?) {
        self.requiredRingFill = requiredRingFill
        self.memberAndAgeRequirements = memberAndAgeRequirements
    }

    func readyAt(for voucher: Voucher) -> Date? {
        guard let requirements = memberAndAgeRequirements,
              let recycler = voucher.recycler,
              recycler.membersCount >= requirements.minimumMembers,
              let enteredAt = recycler.enteredAt else { return nil }

        return enteredAt.addingTimeInterval(requirements.delay)
    }
}

/// Both the member minimum and time since confirmed inclusion must be satisfied.
public struct MemberAndAgeRequirements: Equatable, Sendable {
    public let minimumMembers: UInt32
    public let delay: TimeInterval

    public init(minimumMembers: UInt32, delay: TimeInterval) {
        self.minimumMembers = minimumMembers
        self.delay = delay
    }
}
