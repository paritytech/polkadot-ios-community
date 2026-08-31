import Foundation
import AsyncExtensions
import ChainRegistry
import PolkadotUI
import StructuredConcurrency

@MainActor
protocol ChainStatusProviding: AnyObject {
    func configurationStream() -> AnyAsyncSequence<any HashableContentConfiguration>
}

/// Feeds the tab bar peek panel with per-chain connection status.
///
/// The subject always holds a configuration, so the first render carries a complete row set
/// and the trailing button exists from launch instead of popping in.
@MainActor
final class ChainStatusProvider {
    private static let connectDebounce: Duration = .milliseconds(300)

    private let networkStatusService: NetworkStatusProviding
    private let chainRegistry: ChainRegistryProtocol
    private let logger: LoggerProtocol

    private let configurationSubject: AsyncCurrentValueSubject<any HashableContentConfiguration>

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
        configurationSubject = AsyncCurrentValueSubject(
            Self.makeConfiguration(statuses: seededStatuses, names: [:])
        )
    }

    deinit {
        statusTasks.forEach { $0.cancel() }
        chainRegistry.chainsUnsubscribe(self)
    }
}

extension ChainStatusProvider: ChainStatusProviding {
    func configurationStream() -> AnyAsyncSequence<any HashableContentConfiguration> {
        startObservingIfNeeded()

        return configurationSubject.eraseToAnyAsyncSequence()
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
        emitConfiguration()
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
        emitConfiguration()
    }

    func emitConfiguration() {
        configurationSubject.send(Self.makeConfiguration(statuses: statuses, names: names))
    }

    static func makeConfiguration(
        statuses: [ChainConnectionTarget: NetworkStatus],
        names: [ChainConnectionTarget: String]
    ) -> any HashableContentConfiguration {
        let rows = ChainConnectionTarget.allCases.map { target in
            let state = (statuses[target] ?? .connecting).connectionState

            return ChainConnectionStatusViewModel(
                id: target.chainId,
                title: names[target] ?? target.fallbackTitle,
                state: state,
                stateTitle: state.localizedTitle
            )
        }

        return SwiftUIContentConfiguration(view: ChainConnectionStatusView(rows: rows))
    }
}
