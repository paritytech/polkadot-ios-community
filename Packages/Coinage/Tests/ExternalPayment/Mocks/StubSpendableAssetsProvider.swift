import Foundation
import os
@testable import Coinage

/// Scripted `SpendableAssetsProviding`: one bucket set per scope; an absent scope answers `nil`
/// (no verdicts yet). Records the scopes it was asked for.
final class StubSpendableAssetsProvider: SpendableAssetsProviding, @unchecked Sendable {
    private struct State {
        var assetsByScope: [SpendScope: SpendableAssets] = [:]
        var error: Error?
        var requestedScopes: [SpendScope] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(assets: SpendableAssets? = nil, scope: SpendScope = .spendable) {
        if let assets { set(assets, for: scope) }
    }

    func set(_ assets: SpendableAssets?, for scope: SpendScope) {
        state.withLock { $0.assetsByScope[scope] = assets }
    }

    func setError(_ error: Error?) {
        state.withLock { $0.error = error }
    }

    var requestedScopes: [SpendScope] {
        state.withLock { $0.requestedScopes }
    }

    func spendableAssets(scope: SpendScope) async throws -> SpendableAssets? {
        try state.withLock { state in
            state.requestedScopes.append(scope)
            if let error = state.error { throw error }
            return state.assetsByScope[scope]
        }
    }
}

extension SpendableAssets {
    static let empty = SpendableAssets(
        spendableCoins: [],
        spendableVouchers: [],
        gainingPrivacyCoins: [],
        gainingPrivacyVouchers: [],
        pendingCoins: [],
        pendingVouchers: []
    )

    static func make(
        spendableCoins: [Coin] = [],
        spendableVouchers: [Voucher] = [],
        gainingPrivacyCoins: [Coin] = [],
        gainingPrivacyVouchers: [Voucher] = [],
        pendingCoins: [Coin] = [],
        pendingVouchers: [Voucher] = []
    ) -> SpendableAssets {
        SpendableAssets(
            spendableCoins: spendableCoins,
            spendableVouchers: spendableVouchers,
            gainingPrivacyCoins: gainingPrivacyCoins,
            gainingPrivacyVouchers: gainingPrivacyVouchers,
            pendingCoins: pendingCoins,
            pendingVouchers: pendingVouchers
        )
    }
}
