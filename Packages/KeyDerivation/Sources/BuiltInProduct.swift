import Foundation

/// Governance-reserved product identities for built-in app features.
/// Only `dim2` and `personhood` are wired today; the rest are declared for
/// when those features migrate to the product scheme. Coinage keeps its own
/// derivation layout for now.
public enum BuiltInProduct {
    /// Game (DIM2).
    public static let dim2 = "dim2.dot"
    /// PoI (DIM1).
    public static let poi = "poi.dot"
    /// Funding.
    public static let fund = "fund.dot"
    /// Public light person identity.
    public static let uid = "uid.dot"
    /// Personhood — ring-VRF key domain for full/light person keys.
    public static let personhood = "peopl.dot"
}
