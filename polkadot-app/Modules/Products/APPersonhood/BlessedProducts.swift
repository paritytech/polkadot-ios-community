import Foundation
import Products

enum BlessedProducts {
    static let labels: Set<String> = ["peopl", "dim2", "stash"]

    static func isBlessed(_ productId: ProductId, tld: String) -> Bool {
        guard
            productId.hasSuffix(".\(tld)"),
            let label = ProductHost.name(fromDotDomain: productId)
        else {
            return false
        }

        return labels.contains(label)
    }
}
