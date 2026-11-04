import Foundation
import simd

/// Which studio lights the coins.
///
/// `current` is ours: the exported room lifted, with three softbox panels of our own added in the
/// shader. `tabletop` is the reference's newer studio, coins on a table under a soft window to the
/// upper left, taken exactly as exported, lift and panels off. The tabletop cube ships in debug
/// builds only, under its own file prefix, and only the debug switch can choose it.
enum CoinageStudio: Equatable {
    case current
    case tabletop
    /// The tabletop studio with its dark walls lifted: the same cube, plus a flat lift of light
    /// at lookup, so the room's grey reads at about forty percent rather than twenty.
    case tabletopLifted

    static let tabletopPrefix = "tabletop-"

    /// Linear light added to every sample of the lifted tabletop. sRGB twenty percent is about
    /// 0.033 linear and forty about 0.133, so a tenth takes the one to the other.
    static let tabletopLift: Float = 0.10
}

extension CoinageStudio {
    /// Panels of our own over the lifted tabletop: one above, one to each side and one below, so
    /// a coin tipped to any extreme still mirrors a light rather than the dark beyond the window.
    static let liftedPanels = [
        CoinageAssetStore.Tuning.Panel(direction: SIMD3(0, 0.87, 0.5), halfAngle: 22 * .pi / 180, gain: 0.5),
        CoinageAssetStore.Tuning.Panel(direction: SIMD3(-0.9, 0.1, 0.45), halfAngle: 22 * .pi / 180, gain: 0.45),
        CoinageAssetStore.Tuning.Panel(direction: SIMD3(0.9, 0.1, 0.45), halfAngle: 22 * .pi / 180, gain: 0.45),
        CoinageAssetStore.Tuning.Panel(direction: SIMD3(0, -0.87, 0.5), halfAngle: 22 * .pi / 180, gain: 0.4)
    ]

    /// The material block as this studio wants it. Our lift and panels are the last `tail`
    /// floats; the tabletop studio drops them, the lifted one puts a lift and panels of its own.
    func lighting(ours material: [Float], tail: Int) -> [Float] {
        guard self != .current else { return material }

        let kept = Array(material.prefix(material.count - tail))

        guard self == .tabletopLifted else { return kept + Array(repeating: 0, count: tail) }

        let panels = Self.liftedPanels.flatMap(\.packed)

        return kept + [Self.tabletopLift] + panels + Array(repeating: 0, count: tail - 1 - panels.count)
    }
}

extension CoinageAssetStore.Tuning.Panel {
    /// As the shader reads it: unit direction, cosine of the half angle, gain.
    var packed: [Float] {
        let length = max((direction * direction).sum().squareRoot(), 1e-6)

        return [direction.x / length, direction.y / length, direction.z / length, cos(halfAngle), gain]
    }
}
