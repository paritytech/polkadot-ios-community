import Foundation
import Products
@testable import polkadot_app

/// Scripted `FundingDomainProviding`: one result per entry point, with call counts.
final class StubFundingDomainProvider: FundingDomainProviding, @unchecked Sendable {
    let fundingResult: Result<ProductPage, Error>
    let offrampResult: Result<ProductPage, Error>

    private(set) var fundingCalls = 0
    private(set) var offrampCalls = 0

    init(
        fundingResult: Result<ProductPage, Error> = .failure(FundingDomainError.unavailable),
        offrampResult: Result<ProductPage, Error> = .failure(FundingDomainError.unavailable)
    ) {
        self.fundingResult = fundingResult
        self.offrampResult = offrampResult
    }

    func fundingPage() async throws -> ProductPage {
        fundingCalls += 1
        return try fundingResult.get()
    }

    func offrampPage() async throws -> ProductPage {
        offrampCalls += 1
        return try offrampResult.get()
    }
}
