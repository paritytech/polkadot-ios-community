import Foundation
import Testing
@testable import Products
@testable import polkadot_app

@Suite("RampAction")
struct RampActionTests {
    private struct ResolveFailure: Error {}

    private func makeHost() throws -> ProductHost {
        try #require(ProductHost.parse("getcash.dot", tld: "dot"))
    }

    @Test("top up opens the funding host root")
    func topUpOpensRoot() async throws {
        let host = try makeHost()
        let provider = StubProductHostProvider(syncHostResult: nil, asyncHostResult: .success(host))

        let page = try await RampAction.topUp.resolvePage(label: "funding", using: provider)

        #expect(page.host.name == host.name)
        #expect(page.page == nil)
        #expect(provider.lastLabel == "funding")
    }

    @Test("withdraw opens the getcash withdraw sub-path on the same host")
    func withdrawOpensSubPath() async throws {
        let host = try makeHost()
        let provider = StubProductHostProvider(syncHostResult: nil, asyncHostResult: .success(host))

        let page = try await RampAction.withdraw.resolvePage(label: "funding", using: provider)

        #expect(page.host.name == host.name)
        #expect(page.page == AppConfig.DotNs.getCashWithdrawPage)
        #expect(provider.resolveHostCallCount == 1)
    }

    @Test("unresolved host fails with the ramp error", arguments: RampAction.allCases)
    func unresolvedHostFails(action: RampAction) async {
        let provider = StubProductHostProvider(syncHostResult: nil, asyncHostResult: .success(nil))

        await #expect(throws: RampAction.ResolveError.unresolvedHost) {
            try await action.resolvePage(label: "funding", using: provider)
        }
    }

    @Test("provider errors propagate")
    func providerErrorPropagates() async {
        let provider = StubProductHostProvider(syncHostResult: nil, asyncHostResult: .failure(ResolveFailure()))

        await #expect(throws: ResolveFailure.self) {
            try await RampAction.withdraw.resolvePage(label: "funding", using: provider)
        }
    }
}
