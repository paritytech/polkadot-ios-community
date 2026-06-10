import Foundation
import Operation_iOS
import SubstrateSdk
import Combine
import AsyncExtensions

final class FirebaseFacade {
    static let shared = FirebaseFacade()

    private let firebaseService = FirebaseApplicationService.shared
    private let appConfigProvider: AppConfigProvider = .shared
    private let logger: LoggerProtocol?
    private var chainRegistry: ChainRegistryProtocol?

    private let remoteConfigSubject = AsyncCurrentValueSubject<RemoteAppConfig?>(nil)

    private init(logger: LoggerProtocol? = Logger.shared) {
        self.logger = logger
        firebaseService.delegate = self
    }

    func set(chainRegistry registry: ChainRegistryProtocol) {
        chainRegistry = registry
    }
}

extension FirebaseFacade: RemoteConfigManaging {
    func fetchRemoteConfigValues() {
        Task { [firebaseService] in
            try? await waitUntilReachable()
            firebaseService.fetchRemoteConfigValues()
        }
    }

    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]> {
        firebaseService.asyncWaitChainsForRemoteConfigValues()
    }

    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T> {
        firebaseService.asyncWaitXcmTransfers()
    }

    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T> {
        firebaseService.asyncWaitXcmGeneralConfig()
    }

    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T> {
        firebaseService.asyncWaitW3sMerchants()
    }

    func syncedWeb3SummitGateMode() -> String? {
        firebaseService.syncedWeb3SummitGateMode()
    }

    func syncedWeb3SummitStartGate() -> String? {
        firebaseService.syncedWeb3SummitStartGate()
    }

    func syncedCollectiblesEnabled() -> Bool {
        firebaseService.syncedCollectiblesEnabled()
    }

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig {
        for await config in remoteConfigSubject.compacted() {
            return config
        }

        throw CancellationError()
    }
}

extension FirebaseFacade: RemoteConfigDelegate {
    func remoteConfig(didFinishLoading result: Result<Void, Error>) {
        switch result {
        case .success:
            let config = firebaseService.syncedAppConfig()
            appConfigProvider.apply(config)
            chainRegistry?.syncUp()
            remoteConfigSubject.send(config)
        case let .failure(failure):
            logger?.error(failure.localizedDescription)
        }
    }

    func remoteConfig(appVersionDidChange _: Result<String, Error>) {}
}

private extension FirebaseFacade {
    func waitUntilReachable() async throws {
        guard let reachabilityManager = ReachabilityManager.shared else { return }
        try await reachabilityManager.asyncWaitReachable()
    }
}
