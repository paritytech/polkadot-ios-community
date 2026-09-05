import SwiftUI
import PolkadotUI
import DesignSystem
import Coinage

/// Inline "Payments Privacy Mode" row — the first cell of the Security & Privacy group (the enclosing
/// layout supplies the grouped-cell surface). Three modes on a connected track you can tap or slide
/// between, with a description card reflecting the selection.
///
/// A dumb view: it renders the ``selected`` mode supplied by the Settings view model and reports user
/// input through ``onSelect``; the presenter/interactor own persistence and re-gating.
struct PaymentPrivacyModeCard: View {
    let selected: RecyclingStrategyType
    let onSelect: (RecyclingStrategyType) -> Void

    private let modes = RecyclingStrategyType.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacings.mediumIncreased) {
            header
            selector
            descriptionCard
        }
        .padding(.horizontal, DSSpacings.mediumIncreased)
        .padding(.top, DSSpacings.small)
        .padding(.bottom, DSSpacings.mediumIncreased)
        .sensoryFeedback(.selection, trigger: selected)
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

private extension PaymentPrivacyModeCard {
    var header: some View {
        HStack(spacing: DSSpacings.smallIncreased) {
            Image(systemName: "shield")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.fgSecondary)
                .frame(width: 32, height: 32)

            Text(String(localized: .settingsPrivacymodeTitle))
                .typography(.bodyLarge)
                .foregroundStyle(.fgPrimary)
        }
        .padding(.vertical, DSSpacings.small)
    }
}

// MARK: - Selector

private extension PaymentPrivacyModeCard {
    var selector: some View {
        VStack(spacing: DSSpacings.small) {
            track
            markers
        }
    }

    var track: some View {
        GeometryReader { geo in
            ZStack {
                Capsule()
                    .fill(.bgSurfaceMain)
                    .overlay(Capsule().stroke(.strokePrimary, lineWidth: 1))

                gradientLine
                    .padding(.horizontal, geo.size.width / 6)

                HStack(spacing: 0) {
                    ForEach(modes, id: \.self) { mode in
                        knob(mode)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in select(atPositionX: value.location.x, width: geo.size.width) }
            )
        }
        .frame(height: 44)
    }

    var gradientLine: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: modes.map(\.displayAccentColor),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 4)
    }

    func knob(_ mode: RecyclingStrategyType) -> some View {
        let isSelected = mode == selected
        let size: CGFloat = isSelected ? 40 : 28
        return Image(systemName: mode.displayIconName)
            .font(.system(size: isSelected ? 18 : 13, weight: .semibold))
            .foregroundStyle(mode.displayAccentColor)
            .frame(width: size, height: size)
            .background(mode.displayFillColor, in: Circle())
            .overlay(Circle().stroke(mode.displayAccentColor, lineWidth: isSelected ? 1.5 : 1))
            .shadow(color: isSelected ? mode.displayAccentColor.opacity(0.6) : .clear, radius: 8)
    }

    var markers: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { mode in
                VStack(spacing: DSSpacings.extraTiny) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(mode == selected ? mode.displayAccentColor : .fgTertiary)

                    Text(mode.displayTitle)
                        .typography(.bodySmallEmphasized)
                        .foregroundStyle(mode == selected ? .fgPrimary : .fgSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Description

private extension PaymentPrivacyModeCard {
    var descriptionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacings.extraTiny) {
            Text(selected.displayTitle)
                .typography(.titleMedium)
                .foregroundStyle(.fgPrimary)

            Text(selected.displayDescription)
                .typography(.paragraphMedium)
                .foregroundStyle(.fgSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacings.mediumIncreased)
        .padding(.vertical, DSSpacings.extraMedium)
        .background(.bgSurfaceNested, in: RoundedRectangle(cornerRadius: DSRadii.extraMedium, style: .continuous))
    }
}

// MARK: - Interaction

private extension PaymentPrivacyModeCard {
    /// Maps the touch x-position to the nearest mode, so tapping and sliding both select.
    func select(atPositionX positionX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let ratio = min(max(positionX / width, 0), 0.999)
        let index = Int(ratio * CGFloat(modes.count))
        let mode = modes[index]
        guard mode != selected else { return }
        onSelect(mode)
    }
}

#if DEBUG
    #Preview("PaymentPrivacyModeCard") {
        StatefulPreviewWrapper(RecyclingStrategyType.balanced) { binding in
            PaymentPrivacyModeCard(selected: binding.wrappedValue) { binding.wrappedValue = $0 }
                .dsMenuListCellSurface(position: .first, showsDivider: true)
                .padding()
                .background(Color.bgSurfaceMain)
        }
    }

    private struct StatefulPreviewWrapper<Value, Content: View>: View {
        @State private var value: Value
        private let content: (Binding<Value>) -> Content

        init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
            _value = State(initialValue: initial)
            self.content = content
        }

        var body: some View { content($value) }
    }
#endif
