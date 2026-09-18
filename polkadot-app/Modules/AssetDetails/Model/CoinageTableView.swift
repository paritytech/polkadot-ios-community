import DesignSystem
import SwiftUI

/// Every holding as a coin on a table.
///
/// Denomination picks the material and the shape the way a real coinage does: the four metals
/// cycle with each step up in value, and the shape changes once the metals have been round. That
/// covers sixteen denominations with four of each, and makes a coin recognisable before its value
/// is read.
///
/// Fungibility is wear rather than a bar. Dents are the payments a coin has been through; streaks
/// are how far its recycler still has to go, on the same bucket ladder the bars used. A coin that
/// has never moved and sits in a full ring is unmarked.
struct CoinageTableView: View {
    struct Coin: Equatable, Identifiable {
        let id: String
        /// Denomination index: the value is `0.01 * 2^exponent`.
        let exponent: Int16
        /// One indentation per hop or split.
        let dents: Int
        /// Fungibility bucket. `nil` where there is no recycler record, which wears worst of all.
        let bucket: Int?
    }

    enum Sizing: Equatable {
        /// One size for every coin, so only material and shape carry the denomination.
        case uniform
        /// Grows with the shape tier, so a metal's coins climb in size before the next metal
        /// starts again from small, the way pocket change does.
        case byTier
    }

    let coins: [Coin]
    let sizing: Sizing

    @State private var width: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            for placement in Self.layout(coins, sizing: sizing, width: size.width) {
                Self.draw(placement, in: &context)
            }
        }
        .frame(height: Self.height(coins, sizing: sizing, width: width))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, updated in width = updated }
            }
        )
    }
}

// MARK: - Layout

extension CoinageTableView {
    struct Placement: Equatable {
        let coin: Coin
        let centre: CGPoint
        let diameter: CGFloat
    }

    /// Coins never touch. The gap is what makes a scatter read as loose change rather than as a
    /// stacked chart.
    static let gap: CGFloat = 8

    static func tier(of exponent: Int16) -> Int {
        min(max(Int(exponent) / 4, 0), 3)
    }

    static func diameter(forTier tier: Int, sizing: Sizing) -> CGFloat {
        switch sizing {
        case .uniform: 36
        case .byTier: 28 + 7 * CGFloat(tier)
        }
    }

    /// Alternate rows carry one coin fewer and are centred, which offsets them by half a pitch
    /// without any explicit indent: no coin sits directly below another and the gaps interlock.
    static func layout(_ coins: [Coin], sizing: Sizing, width: CGFloat) -> [Placement] {
        let pitch = diameter(forTier: 3, sizing: sizing) + gap

        guard width >= pitch, !coins.isEmpty else { return [] }

        let columns = max(Int((width + gap) / pitch), 1)
        // Hex packing: rows sit a little closer than a full pitch because they interlock.
        let step = pitch * 0.87

        var placements: [Placement] = []
        var index = 0
        var row = 0

        while index < coins.count {
            let slots = row.isMultiple(of: 2) ? columns : max(columns - 1, 1)
            let count = min(slots, coins.count - index)
            let rowWidth = CGFloat(count) * pitch - gap
            let first = (width - rowWidth) / 2 + pitch / 2

            for column in 0 ..< count {
                let coin = coins[index + column]

                placements.append(
                    Placement(
                        coin: coin,
                        centre: CGPoint(
                            x: first + CGFloat(column) * pitch,
                            y: pitch / 2 + CGFloat(row) * step
                        ),
                        diameter: diameter(forTier: tier(of: coin.exponent), sizing: sizing)
                    )
                )
            }

            index += count
            row += 1
        }

        return placements
    }

    static func height(_ coins: [Coin], sizing: Sizing, width: CGFloat) -> CGFloat {
        let placements = layout(coins, sizing: sizing, width: width)

        return placements.map { $0.centre.y + $0.diameter / 2 }.max() ?? 0
    }
}

// MARK: - Drawing

private extension CoinageTableView {
    static func draw(_ placement: Placement, in context: inout GraphicsContext) {
        let radius = placement.diameter / 2
        let metal = Metal.forExponent(placement.coin.exponent)
        let face = path(
            sides: sides(forTier: tier(of: placement.coin.exponent)),
            centre: placement.centre,
            radius: radius
        )

        context.fill(face, with: metal.shading(centre: placement.centre, radius: radius))

        if metal == .twin {
            let core = path(
                sides: sides(forTier: tier(of: placement.coin.exponent)),
                centre: placement.centre,
                radius: radius * 0.62
            )
            context.fill(core, with: Metal.silver.shading(centre: placement.centre, radius: radius))
        }

        context.stroke(face, with: .color(.black.opacity(0.45)), lineWidth: 1)

        var noise = Noise(seed: placement.coin.id)
        drawStreaks(placement, metal: metal, noise: &noise, in: &context)
        drawDents(placement, noise: &noise, in: &context)
    }

    /// Circle, hexagon, seven-gon, nine-gon. Odd side counts on purpose: they have no parallel
    /// edges, so they cannot be mistaken for the hexagon at a glance.
    static func sides(forTier tier: Int) -> Int {
        [0, 6, 7, 9][min(max(tier, 0), 3)]
    }

    static func path(sides: Int, centre: CGPoint, radius: CGFloat) -> Path {
        guard sides >= 3 else {
            return Path(ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }

        var path = Path()

        for corner in 0 ..< sides {
            let angle = -.pi / 2 + 2 * .pi * CGFloat(corner) / CGFloat(sides)
            let point = CGPoint(
                x: centre.x + radius * cos(angle),
                y: centre.y + radius * sin(angle)
            )

            if corner == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()

        return path
    }

    /// One streak per bucket, so a coin out of a full ring is unstreaked and one out of an empty
    /// ring is covered. No recycler record wears like the worst bucket, matching where the
    /// ordering puts it.
    static func drawStreaks(
        _ placement: Placement,
        metal: Metal,
        noise: inout Noise,
        in context: inout GraphicsContext
    ) {
        let count = placement.coin.bucket ?? CoinageStatusMetrics.maximumBucket
        let radius = placement.diameter / 2

        for _ in 0 ..< count {
            let angle = noise.next() * 2 * .pi
            let distance = radius * (0.15 + 0.6 * noise.next())
            let start = CGPoint(
                x: placement.centre.x + distance * cos(angle),
                y: placement.centre.y + distance * sin(angle)
            )
            let sweep = angle + .pi / 2 + (noise.next() - 0.5)
            let length = radius * (0.2 + 0.3 * noise.next())

            var streak = Path()
            streak.move(to: start)
            streak.addQuadCurve(
                to: CGPoint(x: start.x + length * cos(sweep), y: start.y + length * sin(sweep)),
                control: CGPoint(
                    x: start.x + length * 0.5 * cos(sweep) + (noise.next() - 0.5) * radius * 0.3,
                    y: start.y + length * 0.5 * sin(sweep) + (noise.next() - 0.5) * radius * 0.3
                )
            )

            context.stroke(
                streak,
                with: .color(metal.scuff),
                style: StrokeStyle(lineWidth: max(radius * 0.05, 0.7), lineCap: .round)
            )
        }
    }

    /// A dent is a pit, so it is drawn as a shadow with a lit lower edge rather than as a dot.
    static func drawDents(_ placement: Placement, noise: inout Noise, in context: inout GraphicsContext) {
        let radius = placement.diameter / 2
        let size = max(radius * 0.17, 2)

        for _ in 0 ..< min(placement.coin.dents, 9) {
            let angle = noise.next() * 2 * .pi
            let distance = radius * (0.2 + 0.55 * noise.next())
            let centre = CGPoint(
                x: placement.centre.x + distance * cos(angle),
                y: placement.centre.y + distance * sin(angle)
            )
            let pit = Path(ellipseIn: CGRect(
                x: centre.x - size,
                y: centre.y - size,
                width: size * 2,
                height: size * 2
            ))

            context.fill(pit, with: .color(.black.opacity(0.4)))
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: centre.x - size * 0.85,
                    y: centre.y - size * 0.85 + size * 0.3,
                    width: size * 1.7,
                    height: size * 1.7
                )),
                with: .color(.white.opacity(0.35)),
                lineWidth: max(size * 0.3, 0.6)
            )
        }
    }
}

// MARK: - Metals

private extension CoinageTableView {
    enum Metal: CaseIterable {
        case bronze
        case silver
        case gold
        case twin

        /// Metals cycle with every step up in denomination, so neighbouring values never share a
        /// material and a coin is identifiable from its face alone.
        static func forExponent(_ exponent: Int16) -> Metal {
            allCases[min(max(Int(exponent) % 4, 0), 3)]
        }

        /// Sheen is the spread between the two ends of the gradient: bronze is nearly flat, gold
        /// swings hardest.
        var tones: [Color] {
            switch self {
            case .bronze:
                [Color(red: 0.42, green: 0.26, blue: 0.12), Color(red: 0.72, green: 0.50, blue: 0.29)]
            case .silver:
                [Color(red: 0.48, green: 0.51, blue: 0.55), Color(red: 0.95, green: 0.96, blue: 0.98)]
            case .gold,
                 .twin:
                [Color(red: 0.55, green: 0.38, blue: 0.04), Color(red: 1.0, green: 0.90, blue: 0.55)]
            }
        }

        /// Wear shows as bare metal, brighter than the face on a dull material and duller on a
        /// bright one, so it reads on all four.
        var scuff: Color {
            switch self {
            case .bronze: .white.opacity(0.55)
            case .silver: .black.opacity(0.35)
            case .gold,
                 .twin: .white.opacity(0.6)
            }
        }

        func shading(centre: CGPoint, radius: CGFloat) -> GraphicsContext.Shading {
            .linearGradient(
                Gradient(colors: tones),
                startPoint: CGPoint(x: centre.x - radius, y: centre.y - radius),
                endPoint: CGPoint(x: centre.x + radius, y: centre.y + radius)
            )
        }
    }

    /// Deterministic scatter: wear is seeded from the holding's identity, so a coin keeps the same
    /// face across redraws instead of shuffling its dents on every refresh.
    struct Noise {
        private var state: UInt64

        init(seed: String) {
            state = seed.unicodeScalars.reduce(UInt64(0x9E37_79B9_7F4A_7C15)) {
                ($0 &* 31) &+ UInt64($1.value)
            } | 1
        }

        mutating func next() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17

            return CGFloat(state % 100_000) / 100_000
        }
    }
}

#if DEBUG
    extension CoinageTableView {
        /// A spread across every metal, every shape and the whole wear range, for design review.
        /// Live holdings rarely cover more than a couple of buckets at once.
        static let sample: [Coin] = (0 ..< 24).map { index in
            let exponent = Int16(index % 12)
            let wear = [(5, 8), (1, 4), (0, 2), (0, 0), (3, 6), (2, 7)][index % 6]

            return Coin(
                id: "sample-\(index)",
                exponent: exponent,
                dents: wear.0,
                bucket: index % 7 == 6 ? nil : wear.1
            )
        }
    }
#endif
