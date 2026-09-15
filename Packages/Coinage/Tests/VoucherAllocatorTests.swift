import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import Operation_iOS
@testable import Coinage

struct VoucherAllocatorTests {
    private let queries = StubKeyIndexQueries()
    private let mockDelay = MockDelayProvider()
    private let allocator: VoucherAllocator

    init() {
        allocator = VoucherAllocator(
            installationRepository: InMemoryInstallations(current: .test),
            keyIndexQueries: queries,
            delayProvider: mockDelay,
            voucherRepository: AnyDataProviderRepository(StubRepository<Voucher>()),
            keyFactory: VoucherKeypairFactory(entropyManager: MockEntropyManager(entropy: Data(
                repeating: 0x01,
                count: 32
            )))
        )
    }

    @Test("an allocated voucher takes the next index of the current installation")
    func allocateVoucher() async throws {
        queries.maxVoucherItem = 6
        mockDelay.interval = 3_600

        let startTime = Date()
        let voucher = try await allocator.allocate(exponent: -2)
        let endTime = Date()

        #expect(voucher.derivationIndex == CoinageKeyIndex(installation: .test, item: 7))
        #expect(queries.voucherQueries == [.test])
        #expect(voucher.exponent == -2)
        #expect(voucher.recycler == nil)
        #expect(voucher.allocatedAt >= startTime)
        #expect(voucher.allocatedAt <= endTime)
        #expect(voucher.readyAt == voucher.allocatedAt.addingTimeInterval(3_600))
    }

    @Test("an installation with no vouchers yet starts at item zero")
    func firstItem() async throws {
        queries.maxVoucherItem = nil

        let voucher = try await allocator.allocate(exponent: 0)

        #expect(voucher.derivationIndex == CoinageKeyIndex(installation: .test, item: 0))
    }

    @Test("propagates errors from the index query")
    func allocationFailures() async throws {
        queries.error = InstallationStubError.unreachable

        await #expect(throws: InstallationStubError.unreachable) {
            try await allocator.allocate(exponent: 0)
        }
    }
}

// MARK: - Mocks

private extension VoucherAllocatorTests {
    final class MockDelayProvider: VoucherDelayProviderProtocol {
        var interval: TimeInterval = 0
        func timeInterval() -> TimeInterval {
            interval
        }
    }
}
