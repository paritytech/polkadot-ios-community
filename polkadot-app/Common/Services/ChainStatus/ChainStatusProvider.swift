import Foundation
import AsyncExtensions
import PolkadotUI
import StructuredConcurrency

@MainActor
protocol ChainStatusProviding: AnyObject {
    func statusStream() -> AnyAsyncSequence<[ChainConnectionStatusViewModel]>
}

/// Per-chain connection status. Emits rows rather than a hosted configuration, so a host
/// wraps them however it presents them — the tab bar's top strip and its peek panel.
///
/// One shared instance. The subject always holds a row set, so the first render carries a
/// complete set and a host subscribing later sees live state rather than a re-seed.
@MainActor
final class ChainStatusProvider {
    private static let connectDebounce: Duration = .milliseconds(300)

    private let networkStatusService: NetworkStatusProviding
    private let latencyProvider: ChainLatencyProviding
    private let blockProvider: ChainBlockProviding
    private let logger: LoggerProtocol

    private let rowsSubject: AsyncCurrentValueSubject<[ChainConnectionStatusViewModel]>

    private var statuses: [ChainConnectionTarget: NetworkStatus]
    private var latencies: [ChainConnectionTarget: Duration] = [:]
    private var blocks: [ChainConnectionTarget: ChainBlockInfo] = [:]
    private var connectedSince: [ChainConnectionTarget: Date] = [:]
    private var statusTasks: [Task<Void, Never>] = []
    private var isObserving = false

    init(
        networkStatusService: NetworkStatusProviding,
        latencyProvider: ChainLatencyProviding,
        blockProvider: ChainBlockProviding,
        logger: LoggerProtocol
    ) {
        self.networkStatusService = networkStatusService
        self.latencyProvider = latencyProvider
        self.blockProvider = blockProvider
        self.logger = logger

        let seededStatuses = ChainConnectionTarget.allCases
            .reduce(into: [ChainConnectionTarget: NetworkStatus]()) { $0[$1] = .connecting }

        statuses = seededStatuses
        rowsSubject = AsyncCurrentValueSubject(
            Self.makeRows(
                statuses: seededStatuses,
                latencies: [:],
                blocks: [:],
                connectedSince: [:]
            )
        )
    }

    deinit {
        statusTasks.forEach { $0.cancel() }
    }
}

extension ChainStatusProvider: ChainStatusProviding {
    func statusStream() -> AnyAsyncSequence<[ChainConnectionStatusViewModel]> {
        startObservingIfNeeded()

        return rowsSubject.eraseToAnyAsyncSequence()
    }
}

private extension ChainStatusProvider {
    func startObservingIfNeeded() {
        guard !isObserving else {
            return
        }

        isObserving = true

        // Sampling runs for the app's lifetime because the top status strip is permanent.
        // A host closing its subscription does not pause sampling.
        latencyProvider.setActive(true)
        blockProvider.setActive(true)

        statusTasks = ChainConnectionTarget.allCases.map { target in
            observeStatus(for: target)
        } + [observeLatencies(), observeBlocks()]
    }

    func observeStatus(for target: ChainConnectionTarget) -> Task<Void, Never> {
        Task { [weak self, networkStatusService, logger] in
            let statusStream = networkStatusService
                .statusStream(for: [target.chainId])
                .withDebounce(for: Self.connectDebounce) { $0 == .connected }

            do {
                for try await status in statusStream {
                    self?.handleStatusUpdate(status, for: target)
                }
            } catch {
                logger.error("Chain status stream failed for \(target.chainId): \(error)")
            }
        }
    }

    func observeLatencies() -> Task<Void, Never> {
        Task { [weak self, latencyProvider, logger] in
            do {
                for try await latencies in latencyProvider.latencyStream() {
                    self?.handleLatenciesUpdate(latencies)
                }
            } catch {
                logger.error("Chain latency stream failed: \(error)")
            }
        }
    }

    func observeBlocks() -> Task<Void, Never> {
        Task { [weak self, blockProvider, logger] in
            do {
                for try await blocks in blockProvider.blockStream() {
                    self?.handleBlocksUpdate(blocks)
                }
            } catch {
                logger.error("Chain block stream failed: \(error)")
            }
        }
    }

    func handleStatusUpdate(_ status: NetworkStatus, for target: ChainConnectionTarget) {
        let previousStatus = statuses[target]

        guard previousStatus != status else {
            return
        }

        statuses[target] = status

        if status == .connected {
            connectedSince[target] = Date()
        } else {
            connectedSince[target] = nil
            latencies[target] = nil
            blocks[target] = nil
            latencyProvider.clearSamples(for: target)
            // Without this a drop-and-reconnect keeps captioning the row with its pre-drop data.
            blockProvider.clear(for: target)
        }

        emitRows()
    }

    func handleLatenciesUpdate(_ updatedLatencies: [ChainConnectionTarget: Duration]) {
        guard updatedLatencies != latencies else {
            return
        }

        latencies = updatedLatencies
        emitRows()
    }

    func handleBlocksUpdate(_ updatedBlocks: [ChainConnectionTarget: ChainBlockInfo]) {
        guard updatedBlocks != blocks else {
            return
        }

        blocks = updatedBlocks
        emitRows()
    }

    func emitRows() {
        rowsSubject.send(
            Self.makeRows(
                statuses: statuses,
                latencies: latencies,
                blocks: blocks,
                connectedSince: connectedSince
            )
        )
    }

    static func makeRows(
        statuses: [ChainConnectionTarget: NetworkStatus],
        latencies: [ChainConnectionTarget: Duration],
        blocks: [ChainConnectionTarget: ChainBlockInfo],
        connectedSince: [ChainConnectionTarget: Date]
    ) -> [ChainConnectionStatusViewModel] {
        ChainConnectionTarget.allCases.map { target in
            let state = (statuses[target] ?? .connecting).connectionState
            let block = state == .connected ? blocks[target] : nil

            return ChainConnectionStatusViewModel(
                id: target.chainId,
                title: target.title,
                state: state,
                stateTitle: state.localizedTitle,
                latency: state == .connected ? latencies[target] : nil,
                lastBlockDate: block?.receivedAt,
                finalizedAdvancedAt: block?.finalizedAdvancedAt,
                connectedSince: connectedSince[target],
                thresholds: target.healthThresholds,
                icon: target.statusIcon
            )
        }
    }
}
