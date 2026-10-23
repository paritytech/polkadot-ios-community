import Testing

@testable import polkadot_app

@Suite("BlessedProducts")
struct BlessedProductsTests {
    @Test(arguments: ["peopl.testnet", "dim2.testnet", "stash.testnet"])
    func blessedLabelOnTheCurrentNetwork(productId: String) {
        #expect(BlessedProducts.isBlessed(productId, tld: "testnet"))
    }

    @Test(arguments: ["app.peopl.testnet", "peopl.dot", "peoplx.testnet", "game.testnet", "peopl", ""])
    func anythingElseIsNot(productId: String) {
        #expect(!BlessedProducts.isBlessed(productId, tld: "testnet"))
    }
}
