import Foundation
import Products

/// Products the host grants outbound remote access to without prompting.
///
/// The list belongs to the core, which applies it to every permission request a
/// product makes through the protocol. This app also decides product network
/// access in its own code, so it has to reach the same answer or a first-party
/// product is stopped here for access the core already granted.
///
/// Covers remote access only. Device capabilities, account access, balance and
/// identity disclosure keep prompting for these products, matching the core.
enum ProductRemoteTrust {
    /// Mirrors `truapi_platform::REMOTE_PERMISSION_TRUSTED_LABELS`.
    ///
    /// A copy, and a temporary one. The core exports the answer as
    /// `hasTrustedRemotePermissions(productId:)`, but that lands after the pin
    /// this app builds against, so until `host-rust-core` moves past 0.16.0 the
    /// labels are repeated here.
    ///
    /// Replacing it is deleting this type and passing the core function to
    /// `TrustedRemoteProductPermissionRequester` instead. Until then
    /// `theseLabelsMatchTheCore` fails if the two drift.
    private static let labels: Set<String> = ["peopl", "dim2", "stash"]

    /// Whether `productId` names one of those products.
    ///
    /// Matches the label whole, as the core does, so `app.peopl.dot` is a
    /// different product and is not trusted. The root is dropped because it is
    /// the chain TLD and differs per network.
    static func isTrustedForRemoteAccess(productId: String) -> Bool {
        guard let name = ProductHost.name(fromDotDomain: productId) else { return false }

        return labels.contains(name)
    }
}
