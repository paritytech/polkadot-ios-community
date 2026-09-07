import SwiftUI
import PolkadotUI
import DesignSystem
import Coinage

/// Inline "Payments Privacy Mode" row — the first cell of the Security & Privacy group (the enclosing
/// layout supplies the grouped-cell surface). Three modes as lit spheres resting in a recessed groove that
/// carries a stepped speed-to-privacy scale; tap a mode to switch in place, or drag a sphere and it snaps
/// to the nearest mode on release. A description card reflects the selection.
///
/// A dumb view: it renders the ``selected`` mode supplied by the Settings view model and reports user
/// input through ``onSelect``; the presenter/interactor own persistence and re-gating.
struct PaymentPrivacyModeCard: View {
    let selected: RecyclingStrategyType
    let onSelect: (RecyclingStrategyType) -> Void

    private let modes = RecyclingStrategyType.allCases

    /// Fractional mode index under the finger while dragging; `nil` when the selection is settled.
    @State private var dragFraction: CGFloat?
    /// The scale mark the drag last crossed — the haptic grain of a drag.
    @State private var markIndex = 0
    /// How long the dragged sphere's glyph/accent cross-fade runs, shortened as the drag speeds up.
    @State private var dragFadeDuration = Metrics.slowDragFade
    @State private var lastDragX: CGFloat?
    @State private var lastDragTime: Date?

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
        .sensoryFeedback(.selection, trigger: markIndex)
    }
}

// MARK: - Header

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
            GeometryReader { geo in
                let width = geo.size.width
                ZStack {
                    trackGroove(width: width)
                    TickScale(start: centerX(0, width: width), end: centerX(lastIndex, width: width))
                    circles(width: width)
                }
                .frame(width: width, height: Metrics.boxHeight)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width))
            }
            .frame(height: Metrics.boxHeight)

            GeometryReader { geo in
                markersRow(width: geo.size.width)
            }
            .frame(height: Metrics.selectedMarker + Metrics.markerGlowBlur)

            labelsRow
        }
    }

    func trackGroove(width: CGFloat) -> some View {
        // The floor is the card's own surface taken a shade down — a recess, not a darker token that would
        // read as a hole punched through the card. Depth comes from the two inner shadows below.
        let floor = Color.bgSurfaceContainer.blended(with: .bgSurfaceMain, fraction: 0.4)
        // The shadow tokens are the same black in every theme, so on the light themes' near-white floor a
        // fixed alpha reads as a bruise; soften it by the floor's luminance (untouched on the dark floor).
        let recess = Color.shadowMedium.opacity(0.5).softened(on: floor)
        // Two copies of the groove a point above and below it, covered by the opaque floor: what stays
        // visible is the lit lip along the top and bottom edges only, never a full outline.
        return ZStack {
            Capsule().fill(Color.bgSurfaceNested).offset(y: -1)
            Capsule().fill(Color.bgSurfaceNested).offset(y: 1)
            Capsule()
                .fill(
                    floor
                        .shadow(.inner(color: recess, radius: 6, y: 3))
                        .shadow(.inner(color: recess, radius: 5, y: 7))
                )
        }
        .frame(width: width, height: Metrics.trackHeight)
    }

    func circles(width: CGFloat) -> some View {
        ZStack {
            ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                ModeCircleView(
                    mode: mode,
                    isSelected: index == highlightedIndex,
                    hasGlow: dragFraction == nil && index == selectedIndex
                )
                // While dragging, the covered mode hands its place to the dragged sphere below.
                .opacity(dragFraction != nil && index == highlightedIndex ? 0 : 1)
                .position(x: centerX(CGFloat(index), width: width), y: Metrics.boxHeight / 2)
            }

            if let fraction = dragFraction {
                ModeCircleView(
                    mode: modes[highlightedIndex],
                    isSelected: true,
                    hasGlow: false,
                    fadeDuration: dragFadeDuration
                )
                .position(x: centerX(fraction, width: width), y: Metrics.boxHeight / 2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: highlightedIndex)
        .animation(.easeInOut(duration: 0.2), value: dragFraction == nil)
    }

    /// Triangles pinned under their spheres at the inset-based centres, so a marker stays under its mode.
    func markersRow(width: CGFloat) -> some View {
        ZStack {
            ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                ModeMarkerView(mode: mode, isSelected: index == highlightedIndex)
                    .position(x: centerX(CGFloat(index), width: width), y: Metrics.selectedMarker / 2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: highlightedIndex)
    }

    /// Equal-width label columns; the outer labels hug the track ends the way their spheres do, only the
    /// middle one is free to centre.
    var labelsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                Text(mode.displayTitle)
                    .typography(.bodySmallEmphasized)
                    .foregroundStyle(index == highlightedIndex ? .fgPrimary : .fgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: labelAlignment(index))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: highlightedIndex)
    }

    func labelAlignment(_ index: Int) -> Alignment {
        switch index {
        case 0: .leading
        case modes.count - 1: .trailing
        default: .center
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
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

// MARK: - Geometry & interaction

private extension PaymentPrivacyModeCard {
    var selectedIndex: Int { modes.firstIndex(of: selected) ?? 0 }
    var lastIndex: CGFloat { CGFloat(modes.count - 1) }

    /// The mode the visuals track: the one nearest the finger while dragging, else the settled selection.
    var highlightedIndex: Int {
        guard let fraction = dragFraction else { return selectedIndex }
        return Int(fraction.rounded())
    }

    /// Centre of a (possibly fractional) mode position: inset from each edge by half a sphere, then evenly
    /// spread — so the outer modes sit `inset` from the track ends, not a full column-width in.
    func centerX(_ position: CGFloat, width: CGFloat) -> CGFloat {
        Metrics.inset + position * trackStep(width: width)
    }

    /// Distance between neighbouring mode centres.
    func trackStep(width: CGFloat) -> CGFloat {
        guard modes.count > 1 else { return 0 }
        return (width - Metrics.inset * 2) / lastIndex
    }

    /// A single gesture that reads a tap and a drag apart: a touch that never crosses the slop selects the
    /// mode it lands on in place (`dragFraction` stays nil, so nothing travels), while one that does moves a
    /// sphere under the finger and snaps to the nearest mode on release.
    func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard dragFraction != nil || abs(value.translation.width) >= 8 else { return }
                if dragFraction == nil { beginDrag() }
                trackSpeed(locationX: value.location.x, time: value.time, width: width)

                let fraction = fractionAt(value.location.x, width: width)
                dragFraction = fraction

                let scaleStart = centerX(0, width: width)
                markIndex = max(0, Int((centerX(fraction, width: width) - scaleStart) / Metrics.tickStep))
            }
            .onEnded { value in
                lastDragX = nil
                lastDragTime = nil

                if let fraction = dragFraction {
                    // A drag: slide the sphere to its snapped mode, then hand off to the static one there.
                    finishDrag(from: fraction)
                } else {
                    // A tap: select the mode under the finger in place.
                    commit(target: Int(fractionAt(value.location.x, width: width).rounded()))
                }
            }
    }

    /// Animates the dragged sphere the rest of the way to its nearest mode so the selection settles into
    /// place instead of jumping, dropping the drag only once it has arrived — the point the static sphere
    /// takes over.
    func finishDrag(from fraction: CGFloat) {
        let target = Int(fraction.rounded())
        commit(target: target)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dragFraction = CGFloat(target)
        } completion: {
            dragFraction = nil
        }
    }

    func commit(target: Int) {
        let mode = modes[target]
        guard mode != selected else { return }
        onSelect(mode)
    }

    func beginDrag() {
        dragFadeDuration = Metrics.slowDragFade
        lastDragX = nil
        lastDragTime = nil
    }

    /// Follows the finger's speed in mode-widths per second and eases the cross-fade duration towards its
    /// fast end, smoothed so a single jittery sample does not swing it.
    func trackSpeed(locationX: CGFloat, time: Date, width: CGFloat) {
        defer {
            lastDragX = locationX
            lastDragTime = time
        }
        guard let previousX = lastDragX, let previousTime = lastDragTime else { return }
        let elapsed = time.timeIntervalSince(previousTime)
        let step = trackStep(width: width)
        guard elapsed > 0, step > 0 else { return }

        let speed = abs(locationX - previousX) / step / CGFloat(elapsed)
        let reach = min(max(speed / Metrics.fastDragSpeed, 0), 1)
        let target = Metrics.slowDragFade + (Metrics.fastDragFade - Metrics.slowDragFade) * Double(reach)
        dragFadeDuration += (target - dragFadeDuration) * 0.4
    }

    /// The fractional mode index at a touch x, clamped to the outer modes.
    func fractionAt(_ locationX: CGFloat, width: CGFloat) -> CGFloat {
        let step = trackStep(width: width)
        guard step > 0 else { return 0 }
        return min(max((locationX - Metrics.inset) / step, 0), lastIndex)
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
