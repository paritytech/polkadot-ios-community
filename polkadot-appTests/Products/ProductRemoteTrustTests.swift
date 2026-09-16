import Foundation
import Testing
@testable import polkadot_app

@Suite("ProductRemoteTrust")
struct ProductRemoteTrustTests {
    /// The labels are copied from the core until the pin moves past 0.16.0, and
    /// a copy that quietly falls behind is the whole reason this app grew its
    /// own allowlist in the first place. Pin what the core says, so widening
    /// `REMOTE_PERMISSION_TRUSTED_LABELS` without updating the copy fails here
    /// rather than silently leaving a product prompting.
    @Test("The mirrored labels are the ones the core trusts")
    func mirroredLabelsMatchTheCore() {
        for productId in ["peopl.dot", "dim2.dot", "stash.dot"] {
            #expect(
                ProductRemoteTrust.isTrustedForRemoteAccess(productId: productId),
                "\(productId) is trusted by truapi_platform::REMOTE_PERMISSION_TRUSTED_LABELS"
            )
        }
    }

    /// Matches the core: the label is the whole segment above the TLD, so a
    /// product published beneath a trusted one is a different product.
    @Test("A product under a trusted label is not itself trusted")
    func nestedProductsAreNotTrusted() {
        for productId in [
            "app.peopl.dot",
            "peopl",
            "notpeopl.dot",
            "peopl..dot",
            ""
        ] {
            #expect(!ProductRemoteTrust.isTrustedForRemoteAccess(productId: productId), "\(productId)")
        }
    }

    /// The root is the chain TLD and differs per network, so trust follows the
    /// product across networks rather than being pinned to Polkadot.
    @Test("Trust follows the label across networks")
    func trustIsNetworkIndependent() {
        for productId in ["peopl.paseo", "dim2.paseo", "stash.testnet"] {
            #expect(ProductRemoteTrust.isTrustedForRemoteAccess(productId: productId), "\(productId)")
        }
    }
}
