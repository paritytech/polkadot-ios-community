import SwiftUI
import PolkadotUI
import DesignSystem
import Coinage

/// Inline "Payment Privacy Mode" row — the first cell of the Security & Privacy group (the enclosing
/// layout supplies the grouped-cell surface). Three modes on a connected track you can tap or slide
/// between. Self-contained — it reads and writes the shared strategy store, so a change re-gates the
/// whole wallet immediately.
struct PaymentPrivacyModeCard: View {
    private let store: any CoinageRecyclingStrategyProviding
    @State private var selected: RecyclingStrategyType

    init(store: any CoinageRecyclingStrategyProviding = CoinageRecyclingStrategyStore.shared) {
        self.store = store
        _selected = State(initialValue: store.strategy)
    }

    private let modes = RecyclingStrategyType.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Payment Privacy Mode")
                    .typography(.titleLarge)
                    .foregroundStyle(.fgPrimary)

                Text("This setting controls how your payments are processed")
                    .typography(.bodyMedium)
                    .foregroundStyle(.fgSecondary)
            }

            selector
        }
        .padding(DSSpacings.mediumIncreased)
        .sensoryFeedback(.selection, trigger: selected)
        .task {
            do {
                for try await mode in store.strategyStream() {
                    selected = mode
                }
            } catch {}
        }
    }
}

private extension PaymentPrivacyModeCard {
    var selector: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                    option(mode)
                        .frame(maxWidth: .infinity)

                    if index < modes.count - 1 {
                        Image(systemName: "chevron.compact.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.fgTertiary)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in slide(toPositionX: value.location.x, width: geo.size.width) }
            )
        }
        .frame(height: 92)
    }

    func option(_ mode: RecyclingStrategyType) -> some View {
        let isSelected = mode == selected
        return VStack(spacing: 8) {
            Image(systemName: mode.displayIconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(mode.displayColor)
                .frame(width: 52, height: 52)
                .background(mode.displayColor.opacity(isSelected ? 0.22 : 0.10))
                .clipShape(Circle())
                .overlay(Circle().stroke(mode.displayColor, lineWidth: isSelected ? 2 : 0))
                .scaleEffect(isSelected ? 1.06 : 1.0)

            Text(mode.displayTitle)
                .typography(.bodyMedium)
                .foregroundStyle(isSelected ? mode.displayColor : .fgSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    /// Maps the touch x-position to the nearest mode, so tapping and sliding both select.
    func slide(toPositionX positionX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let ratio = min(max(positionX / width, 0), 0.999)
        let index = Int(ratio * CGFloat(modes.count))
        update(to: modes[index])
    }

    func update(to mode: RecyclingStrategyType) {
        guard mode != selected else { return }
        selected = mode
        store.save(strategy: mode)
    }
}
