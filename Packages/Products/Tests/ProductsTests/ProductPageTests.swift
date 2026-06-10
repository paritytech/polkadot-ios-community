import Foundation
import Testing
@testable import Products

struct ProductPageTests {
    // MARK: - fromUrl(_:)

    @Test func fromUrlWithoutPage() {
        let page = ProductPage.fromUrl(URL(string: "https://browse.dot")!)
        #expect(page?.host.toDotDomain() == "browse.dot")
        #expect(page?.page == nil)
    }

    @Test func fromUrlWithRootPath() {
        let page = ProductPage.fromUrl(URL(string: "https://browse.dot/")!)
        #expect(page?.page == nil)
    }

    @Test func fromUrlWithPath() {
        let page = ProductPage.fromUrl(URL(string: "https://browse.dot/onboarding/step")!)
        #expect(page?.host.toDotDomain() == "browse.dot")
        #expect(page?.page == "/onboarding/step")
    }

    @Test func fromUrlKeepsFragmentInRelativePart() {
        let page = ProductPage.fromUrl(URL(string: "https://web3summit.dot.li/#/onboarding")!)
        #expect(page?.host.toDotDomain() == "web3summit.dot")
        #expect(page?.page == "/#/onboarding")
    }

    @Test func fromUrlKeepsQueryInRelativePart() {
        let page = ProductPage.fromUrl(URL(string: "https://browse.dot/onboarding?ref=abc")!)
        #expect(page?.page == "/onboarding?ref=abc")
    }

    @Test func fromUrlRejectsInvalidHost() {
        #expect(ProductPage.fromUrl(URL(string: "https://browse.com/page")!) == nil)
    }

    // MARK: - applied(to:)

    @Test func appliedWithoutPageReturnsBase() {
        let host = ProductHost(rawString: "browse.dot")!
        let base = URL(string: "product://browse.dot/index.html")!
        let result = ProductPage(host: host).applied(to: base)
        #expect(result == base)
    }

    @Test func appliedReplacesEntryFileWithFragmentRoute() {
        let host = ProductHost(rawString: "web3summit.dot")!
        let base = URL(string: "product://web3summit.dot/index.html")!
        let result = ProductPage(host: host, page: "/#/onboarding").applied(to: base)
        #expect(result.absoluteString == "product://web3summit.dot/#/onboarding")
    }

    @Test func appliedReplacesEntryFileWithPath() {
        let host = ProductHost(rawString: "browse.dot")!
        let base = URL(string: "product://browse.dot/index.html")!
        let result = ProductPage(host: host, page: "/onboarding").applied(to: base)
        #expect(result.absoluteString == "product://browse.dot/onboarding")
    }

    @Test func appliedNormalizesPageMissingLeadingSlash() {
        let host = ProductHost(rawString: "web3summit.dot")!
        let base = URL(string: "product://web3summit.dot/index.html")!
        let result = ProductPage(host: host, page: "#/onboarding").applied(to: base)
        #expect(result.absoluteString == "product://web3summit.dot/#/onboarding")
    }
}
