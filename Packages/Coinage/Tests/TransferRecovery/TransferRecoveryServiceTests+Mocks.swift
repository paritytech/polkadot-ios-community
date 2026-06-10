import Foundation
import Combine
import SubstrateSdk
import KeyDerivation
import os
import StructuredConcurrency
import AsyncExtensions
import SubstrateOperation
import BigInt
@testable import Coinage

extension TransferRecoveryServiceTests {
    /// Controls `chain_subscribeFinalizedHeads` emissions for recovery tests.
    ///
    /// Emits one `Block.Header` per entry in `scheduledBlockNumbers` (default: `[1_000]`),
    /// then **terminates the stream**. Tests that leave WAL entries unresolved rely on stream
    /// termination to unblock `recover()` — no timeout needed.
    final class MockBlockNumberProvider: BlockInfoProviding {
        var blockNumber: BlockNumber = 1_000
        var blockHash: BlockHashData = Data(repeating: 0x00, count: 32)
        var scheduledBlockNumbers: [UInt32] = [1_000]

        func fetchCurrent() async throws -> BlockNumber {
            blockNumber
        }

        func fetchCurrentHash() async throws -> BlockHashData {
            blockHash
        }

        func fetchFinalized() async throws -> BlockNumber {
            blockNumber
        }

        func fetchFinalizedHash() async throws -> SubstrateSdk.BlockHashData {
            blockHash
        }

        func fetchBlockHash(_: SubstrateSdk.BlockNumber) async throws -> SubstrateSdk.BlockHashData {
            blockHash
        }

        func subscribeFinalizedHeads() -> AnyAsyncSequence<Block.Header> {
            let numbers = scheduledBlockNumbers
            return AsyncStream<Block.Header> { continuation in
                Task {
                    for blockNumber in numbers {
                        await Task.yield()
                        let hex = String(blockNumber, radix: 16)
                        let json = """
                        {"number":"0x\(hex)","parentHash":"0x00","stateRoot":"0x00",\
                        "extrinsicsRoot":"0x00","digest":{"logs":[]}}
                        """
                        if let header = try? JSONDecoder().decode(Block.Header.self, from: Data(json.utf8)) {
                            continuation.yield(header)
                        }
                    }
                    continuation.finish()
                }
            }.eraseToAnyAsyncSequence()
        }
    }

    actor MockTransferWALStore: TransferWALStoring {
        private(set) var savedEntries: [TransferWALEntry] = []
        private(set) var deletedIds: [UUID] = []
        nonisolated(unsafe) var fetchAllResult: [TransferWALEntry] = []

        func save(_ entry: TransferWALEntry) async throws {
            savedEntries.append(entry)
        }

        func update(id _: UUID, checkpointBlock _: Coinage.CheckpointBlock) async throws {
            // Not tested in recovery scenarios
        }

        func fetchAll() async throws -> [TransferWALEntry] {
            fetchAllResult
        }

        func save(contentsOf entries: [TransferWALEntry]) async throws {
            savedEntries.append(contentsOf: entries)
        }

        func delete(id: UUID) async throws {
            deletedIds.append(id)
        }
    }

    final class MockCoinService: CoinServiceProtocol, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (
            savedCoins: [Coin](),
            markedSpentIds: [String](),
            markedAvailableIds: [String]()
        ))

        var savedCoins: [Coin] { state.withLock { $0.savedCoins } }
        var markedSpentIds: [String] { state.withLock { $0.markedSpentIds } }
        var markedAvailableIds: [String] { state.withLock { $0.markedAvailableIds } }

        func fetchAllCoins() async throws -> [Coin] { [] }

        func save(coins: [Coin]) async throws {
            state.withLock { $0.savedCoins.append(contentsOf: coins) }
        }

        func markSpent(coinIds: [String]) async throws {
            state.withLock { $0.markedSpentIds.append(contentsOf: coinIds) }
        }

        func markRecycling(coinIds _: [String]) async throws {
            // Not used in recovery
        }

        func markAvailable(coinIds: [String]) async throws {
            state.withLock { $0.markedAvailableIds.append(contentsOf: coinIds) }
        }

        func markPendingTransfer(coinIds _: [String]) async throws {
            // Not used in recovery
        }
    }

    final class MockVoucherService: VoucherServiceProtocol, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (
            deletedIdentifiers: [String](),
            savedVouchers: [Voucher](),
            markedAvailableIds: [String]()
        ))
        var fetchAllResult: [Voucher] = []

        var deletedIdentifiers: [String] { state.withLock { $0.deletedIdentifiers } }
        var savedVouchers: [Voucher] { state.withLock { $0.savedVouchers } }
        var markedAvailableIds: [String] { state.withLock { $0.markedAvailableIds } }

        func load(
            amount _: BigUInt,
            externalAssetHolder _: any WalletManaging,
            breakdownContext _: DenominationBreakdownContext
        ) async throws {
            // Not used in recovery
        }

        func fetchAll() async throws -> [Voucher] {
            fetchAllResult
        }

        func fetchAvailableInRecycler() async throws -> [Coinage.Voucher] {
            []
        }

        func markPendingOnboarding(identifiers _: [String]) async throws {
            // Not used in recovery
        }

        func save(vouchers: [Voucher]) async throws {
            state.withLock { $0.savedVouchers.append(contentsOf: vouchers) }
        }

        func delete(identifiers: [String]) async throws {
            state.withLock { $0.deletedIdentifiers.append(contentsOf: identifiers) }
        }

        func markPendingTransfer(identifiers _: [String]) async throws {
            // Not used in recovery
        }

        func markAvailable(identifiers: [String]) async throws {
            let updated = fetchAllResult
                .filter { identifiers.contains($0.identifier) }
                .map { $0.withLocalState(.available) }
            state.withLock {
                $0.savedVouchers.append(contentsOf: updated)
                $0.markedAvailableIds.append(contentsOf: identifiers)
            }
        }
    }

    final class MockCoinOnChainQuery: CoinOnChainQuerying, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (
            callCount: 0,
            queue: [[CoinSyncResult.OnChainCoin?]]()
        ))

        var fetchCoinsCallCount: Int { state.withLock { $0.callCount } }

        /// Default result returned when the queue is exhausted.
        var fetchCoinsResults: [CoinSyncResult.OnChainCoin?] = []

        /// Enqueues a result set to be returned on the next call (FIFO).
        func enqueue(_ results: [CoinSyncResult.OnChainCoin?]) {
            state.withLock { $0.queue.append(results) }
        }

        func fetchCoins(for _: [Data], atBlockHash _: Data?) async throws -> [CoinSyncResult.OnChainCoin?] {
            state.withLock {
                $0.callCount += 1
                return $0.queue.isEmpty ? fetchCoinsResults : $0.queue.removeFirst()
            }
        }

        func awaitAllCoinsOnChain(for _: [Data]) async throws {
            // Not used in recovery
        }

        func awaitAllCoinsOffChain(for _: [Data]) async throws {
            // Not used in recovery
        }
    }

    final class MockVoucherOnChainQuery: VoucherOnChainQuerying, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (
            callCount: 0,
            queue: [[VoucherOnChainInfo?]]()
        ))

        var fetchVouchersCallCount: Int { state.withLock { $0.callCount } }

        var fetchVouchersResults: [VoucherOnChainInfo?] = []

        func enqueue(_ results: [VoucherOnChainInfo?]) {
            state.withLock { $0.queue.append(results) }
        }

        func fetchVouchers(for _: [UInt32], atBlockHash _: Data?) async throws -> [VoucherOnChainInfo?] {
            state.withLock {
                $0.callCount += 1
                return $0.queue.isEmpty ? fetchVouchersResults : $0.queue.removeFirst()
            }
        }
    }

    final class MockVoucherKeyFactory: VoucherKeyDeriving {
        typealias Model = Voucher

        func derivePublicKey(for voucher: Voucher) throws -> Data {
            var result = Data(repeating: 0xFF, count: 32)
            let bytes = withUnsafeBytes(of: voucher.derivationIndex) { Array($0) }
            for (i, byte) in bytes.enumerated() {
                result[i] = byte
            }
            return result
        }

        func derivePrivateKey(for _: Voucher) throws -> Data {
            throw NSError(domain: "MockVoucherKeyFactory", code: -1, userInfo: nil)
        }

        func createKeyManager(for _: Voucher) throws -> any BandersnatchKeyManaging {
            throw NSError(domain: "MockVoucherKeyFactory", code: -1, userInfo: nil)
        }
    }

    final class MockCoinKeyFactory: CoinKeyDeriving {
        typealias Model = Coin

        func derivePublicKey(for coin: Coin) throws -> Data {
            var result = Data(repeating: 0, count: 32)
            let bytes = withUnsafeBytes(of: coin.derivationIndex) { Array($0) }
            for (i, byte) in bytes.enumerated() {
                result[i] = byte
            }
            return result
        }

        func derivePrivateKey(for _: Coin) throws -> Data {
            throw NSError(domain: "MockCoinKeyFactory", code: -1, userInfo: nil)
        }
    }
}
