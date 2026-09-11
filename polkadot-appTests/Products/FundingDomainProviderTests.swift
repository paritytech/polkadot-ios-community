import Foundation
import Testing
import Products
@testable import polkadot_app

@Suite("FundingDomainProvider")
struct FundingDomainProviderTests {
    private func makeProvider(
        tld: String? = "dot",
        fundingUrl: String? = "https://getcash.dot",
        offrampUrl: String? = "https://getcash.dot/offramp"
    ) -> FundingDomainProvider {
        let config = RemoteAppConfig(
            identityBackendUrl: nil,
            ipfsGatewayUrl: nil,
            gameDashboardUrl: nil,
            dotNsResolver: nil,
            dotNsNameRegistry: nil,
            coinageInstanceId: nil,
            fundingDomain: nil,
            fundingUrl: fundingUrl.flatMap { URL(string: $0) },
            offrampUrl: offrampUrl.flatMap { URL(string: $0) }
        )
        return FundingDomainProvider(
            hostProvider: ProductHostFactory(tldProvider: StubDotNsTldProvider(tld: tld)),
            remoteConfig: { config }
        )
    }

    @Test("funding page is the URL's host with no path")
    func fundingPage() async throws {
        let page = try await makeProvider().fundingPage()

        #expect(page.host.name == "getcash")
        #expect(page.page == nil)
    }

    @Test("offramp page keeps the URL path so a product can serve withdraw from a sub-page")
    func offrampPageKeepsPath() async throws {
        let page = try await makeProvider().offrampPage()

        #expect(page.host.name == "getcash")
        #expect(page.page == "/offramp")
    }

    @Test("a missing remote key is unavailable")
    func missingKeyIsUnavailable() async {
        await #expect(throws: FundingDomainError.unavailable) {
            try await makeProvider(offrampUrl: nil).offrampPage()
        }
    }

    @Test("a host outside the chain TLD is unavailable")
    func foreignHostIsUnavailable() async {
        await #expect(throws: FundingDomainError.unavailable) {
            try await makeProvider(fundingUrl: "https://getcash.com").fundingPage()
        }
    }

    @Test("an unresolved TLD propagates the resolver error")
    func unresolvedTldPropagates() async {
        await #expect(throws: DotNsTldError.unavailable) {
            try await makeProvider(tld: nil).fundingPage()
        }
    }
}
