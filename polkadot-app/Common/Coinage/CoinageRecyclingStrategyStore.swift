import Foundation
import Coinage
import AsyncExtensions
@preconcurrency import Keystore_iOS

/// App-side implementation of ``CoinageRecyclingStrategyProviding`` backed by `SettingsManager`.
/// App-wide (not per-account), defaulting to ``RecyclingStrategyType/minPrivacy`` — the closest match
/// to the legacy hardcoded behaviour, so an upgrade changes what buckets are *called* without changing
/// what is spendable.
final class CoinageRecyclingStrategyStore: CoinageRecyclingStrategyProviding {
    private let settingsManager: SettingsManagerProtocol
    private let subject: AsyncCurrentValueSubject<RecyclingStrategyType>

    init(settingsManager: SettingsManagerProtocol = SettingsManager.shared) {
        self.settingsManager = settingsManager

        let stored = settingsManager.string(for: .coinageRecyclingStrategy)
            .flatMap(RecyclingStrategyType.init(rawValue:)) ?? .minPrivacy
        subject = AsyncCurrentValueSubject<RecyclingStrategyType>(stored)
    }

    var strategy: RecyclingStrategyType {
        subject.value
    }

    func strategyStream() -> AnyAsyncSequence<RecyclingStrategyType> {
        subject.eraseToAnyAsyncSequence()
    }

    func save(strategy: RecyclingStrategyType) {
        settingsManager.set(string: strategy.rawValue, for: .coinageRecyclingStrategy)
        subject.send(strategy)
    }
}
