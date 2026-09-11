import Foundation
import Testing
@testable import Products
@testable import polkadot_app

@Suite("RampAction")
struct RampActionTests {
    private struct ResolveFailure: Error {}

    private func page(_ path: String?) throws -> ProductPage {
        try ProductPage(host: #require(ProductHost.parse("getcash.dot", tld: "dot")), page: path)
    }

    @Test("top up opens the funding page only")
    func topUpOpensFundingPage() async throws {
        let provider = try StubFundingDomainProvider(fundingResult: .success(page(nil)))

        let resolved = try await RampAction.topUp.resolvePage(using: provider)

        #expect(resolved.host.name == "getcash")
        #expect(resolved.page == nil)
        #expect(provider.fundingCalls == 1)
        #expect(provider.offrampCalls == 0)
    }

    @Test("withdraw opens the offramp page only")
    func withdrawOpensOfframpPage() async throws {
        let provider = try StubFundingDomainProvider(offrampResult: .success(page("/offramp")))

        let resolved = try await RampAction.withdraw.resolvePage(using: provider)

        #expect(resolved.page == "/offramp")
        #expect(provider.offrampCalls == 1)
        #expect(provider.fundingCalls == 0)
    }

    @Test("provider errors propagate", arguments: RampAction.allCases)
    func providerErrorPropagates(action: RampAction) async {
        let provider = StubFundingDomainProvider(
            fundingResult: .failure(ResolveFailure()),
            offrampResult: .failure(ResolveFailure())
        )

        await #expect(throws: ResolveFailure.self) {
            try await action.resolvePage(using: provider)
        }
    }
}
