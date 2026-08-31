import Foundation
import AsyncExtensions
import ChainRegistry
import PolkadotUI
import StructuredConcurrency

@MainActor
protocol ChainStatusProviding: AnyObject {
    func statusStream() -> AnyAsyncSequence<[ChainConnectionStatusViewModel]>
}

/// Per-chain connection status. Emits rows rather than a hosted configuration, so a host
/// wraps them however it presents them — currently only the tab bar peek panel.
///
/// One shared instance. The subject always holds a row set, so the first render carries a
/// complete set and a host subscribing later sees live state rather than a re-seed.
@MainActor
final class ChainStatusProvider {
    private static let connectDebounce: Duration = .milliseconds(300)

    private let networkStatusService: NetworkStatusProviding
    private let chainRegistry: ChainRegistryProtocol
    private let logger: LoggerProtocol

    private let rowsSubject: AsyncCurrentValueSubject<[ChainConnectionStatusViewModel]>

    private var statuses: [ChainConnectionTarget: NetworkStatus]
    private var names: [ChainConnectionTarget: String] = [:]
    private var statusTasks: [Task<Void, Never>] = []
    private var isObserving = false

    init(
        networkStatusService: NetworkStatusProviding,
        chainRegistry: ChainRegistryProtocol,
        logger: LoggerProtocol
    ) {
        self.networkStatusService = networkStatusService
        self.chainRegistry = chainRegistry
        self.logger = logger

        let seededStatuses = ChainConnectionTarget.allCases
            .reduce(into: [ChainConnectionTarget: NetworkStatus]()) { $0[$1] = .connecting }

        statuses = seededStatuses
        rowsSubject = AsyncCurrentValueSubject(
            Self.makeRows(statuses: seededStatuses, names: [:])
        )
    }

    deinit {
        statusTasks.forEach { $0.cancel() }
        chainRegistry.chainsUnsubscribe(self)
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

        statusTasks = ChainConnectionTarget.allCases.map { target in
            observeStatus(for: target)
        }

        // Status updates are de-duplicated, so a chain that connects before the registry loads
        // never emits again — chain names have to come from their own subscription.
        chainRegistry.chainsSubscribe(self, runningInQueue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleChainDataUpdate()
            }
        }
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

    func handleStatusUpdate(_ status: NetworkStatus, for target: ChainConnectionTarget) {
        guard statuses[target] != status else {
            return
        }

        statuses[target] = status
        emitRows()
    }

    func handleChainDataUpdate() {
        let updatedNames = ChainConnectionTarget.allCases
            .reduce(into: [ChainConnectionTarget: String]()) {
                $0[$1] = chainRegistry.getChain(for: $1.chainId)?.name
            }

        guard updatedNames != names else {
            return
        }

        names = updatedNames
        emitRows()
    }

    func emitRows() {
        rowsSubject.send(Self.makeRows(statuses: statuses, names: names))
    }

    static func makeRows(
        statuses: [ChainConnectionTarget: NetworkStatus],
        names: [ChainConnectionTarget: String]
    ) -> [ChainConnectionStatusViewModel] {
        ChainConnectionTarget.allCases.map { target in
            let state = (statuses[target] ?? .connecting).connectionState

            return ChainConnectionStatusViewModel(
                id: target.chainId,
                title: names[target] ?? target.fallbackTitle,
                state: state,
                stateTitle: state.localizedTitle
            )
        }
    }
}
