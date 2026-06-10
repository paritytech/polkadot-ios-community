import Foundation
import Testing
@testable import Products

struct ProductHostTests {
    // MARK: - init?(rawString:)

    @Test func simpleDotDomain() {
        let host = ProductHost(rawString: "browse.dot")
        #expect(host != nil)
    }

    @Test func dotLiDomain() {
        let host = ProductHost(rawString: "browse.dot.li")
        #expect(host != nil)
    }

    @Test func subdomainDotDomain() {
        let host = ProductHost(rawString: "sub.browse.dot")
        #expect(host != nil)
    }

    @Test func subdomainDotLiDomain() {
        let host = ProductHost(rawString: "sub.browse.dot.li")
        #expect(host != nil)
    }

    @Test func deeplyNestedSubdomain() {
        let host = ProductHost(rawString: "a.b.c.browse.dot")
        #expect(host != nil)
    }

    @Test func deeplyNestedSubdomainDotLi() {
        let host = ProductHost(rawString: "a.b.c.browse.dot.li")
        #expect(host != nil)
    }

    @Test func rejectsPlainString() {
        #expect(ProductHost(rawString: "browse") == nil)
    }

    @Test func rejectsEmptyString() {
        #expect(ProductHost(rawString: "") == nil)
    }

    @Test func rejectsDotOnly() {
        #expect(ProductHost(rawString: ".dot") == nil)
    }

    @Test func rejectsWrongTld() {
        #expect(ProductHost(rawString: "browse.com") == nil)
    }

    @Test func rejectsPartialDotLi() {
        #expect(ProductHost(rawString: "browse.li") == nil)
    }

    @Test func rejectsDotLiWithoutName() {
        #expect(ProductHost(rawString: ".dot.li") == nil)
    }

    // MARK: - name

    @Test func nameForSimpleDotDomain() {
        let host = ProductHost(rawString: "browse.dot")
        #expect(host?.name == "browse")
    }

    @Test func nameForDotLiDomain() {
        let host = ProductHost(rawString: "browse.dot.li")
        #expect(host?.name == "browse")
    }

    @Test func nameForSubdomainDotDomain() {
        let host = ProductHost(rawString: "sub.browse.dot")
        #expect(host?.name == "sub.browse")
    }

    @Test func nameForSubdomainDotLiDomain() {
        let host = ProductHost(rawString: "sub.browse.dot.li")
        #expect(host?.name == "sub.browse")
    }

    @Test func nameForDeepSubdomain() {
        let host = ProductHost(rawString: "a.b.c.dot")
        #expect(host?.name == "a.b.c")
    }

    // MARK: - toDotDomain()

    @Test func toDotDomainForSimple() {
        let host = ProductHost(rawString: "browse.dot")
        #expect(host?.toDotDomain() == "browse.dot")
    }

    @Test func toDotDomainForDotLi() {
        let host = ProductHost(rawString: "browse.dot.li")
        #expect(host?.toDotDomain() == "browse.dot")
    }

    @Test func toDotDomainForSubdomain() {
        let host = ProductHost(rawString: "sub.browse.dot")
        #expect(host?.toDotDomain() == "sub.browse.dot")
    }

    @Test func toDotDomainForSubdomainDotLi() {
        let host = ProductHost(rawString: "sub.browse.dot.li")
        #expect(host?.toDotDomain() == "sub.browse.dot")
    }

    // MARK: - fromUrl(_:)

    @Test func fromUrlWithDotDomain() {
        let url = URL(string: "https://browse.dot/path")!
        let host = ProductHost.fromUrl(url)
        #expect(host != nil)
        #expect(host?.name == "browse")
    }

    @Test func fromUrlWithSubdomain() {
        let url = URL(string: "https://sub.browse.dot/path")!
        let host = ProductHost.fromUrl(url)
        #expect(host != nil)
        #expect(host?.name == "sub.browse")
    }

    @Test func fromUrlRejectsInvalidHost() {
        let url = URL(string: "https://browse.com/path")!
        #expect(ProductHost.fromUrl(url) == nil)
    }

    // MARK: - fromNavigationDestination(_:)

    @Test func fromNavigationDestinationWithUrl() {
        let host = ProductHost.fromNavigationDestination("https://browse.dot/page")
        #expect(host != nil)
        #expect(host?.name == "browse")
    }

    @Test func fromNavigationDestinationWithRawString() {
        let host = ProductHost.fromNavigationDestination("browse.dot")
        #expect(host != nil)
        #expect(host?.name == "browse")
    }

    @Test func fromNavigationDestinationWithSubdomain() {
        let host = ProductHost.fromNavigationDestination("sub.browse.dot")
        #expect(host != nil)
        #expect(host?.name == "sub.browse")
    }

    @Test func fromNavigationDestinationRejectsInvalid() {
        #expect(ProductHost.fromNavigationDestination("invalid") == nil)
    }
}
