import Foundation
import Operation_iOS
import FirebaseCore
import FirebaseRemoteConfig
import Combine

protocol RemoteConfigDelegate: AnyObject {
    func remoteConfig(didFinishLoading result: Result<Void, Error>)
    func remoteConfig(appVersionDidChange result: Result<String, Error>)
}

extension RemoteConfigDelegate {
    func remoteConfig(didFinishLoading _: Result<Void, Error>) {}
    func remoteConfig(appVersionDidChange _: Result<String, Error>) {}
}

final class FirebaseApplicationService: RemoteConfigManaging {
    static let shared = FirebaseApplicationService()

    // MARK: Properties

    private let remoteConfig: FirebaseRemoteConfig.RemoteConfig

    weak var delegate: (any RemoteConfigDelegate)?
    private let logger: LoggerProtocol = Logger.shared

    // MARK: Initial methods

    private init() {
        #if DEBUG
            var args = ProcessInfo.processInfo.arguments
            args.append("-FIRDebugEnabled")
            ProcessInfo.processInfo.setValue(args, forKey: "arguments")
            FirebaseConfiguration.shared.setLoggerLevel(.info)
        #else
            var args = ProcessInfo.processInfo.arguments
            args.append("-FIRDebugDisabled")
            ProcessInfo.processInfo.setValue(args, forKey: "arguments")
        #endif

        FirebaseApp.configure()
        remoteConfig = FirebaseRemoteConfig.RemoteConfig.remoteConfig()

        configurationRemoteConfigSettings()
    }

    // MARK: Public methods

    func fetchRemoteConfigValues() {
        remoteConfig.fetchAndActivate { [weak self] status, error in
            guard let self else {
                return
            }

            defer {
                handleRemoteConfigStatus(status)
            }

            if let error {
                delegate?.remoteConfig(didFinishLoading: .failure(error))
                return
            }
        }
    }

    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]> {
        asyncWaitForRemoteConfigValues(for: .chains())
    }

    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .xcmTransfers)
    }

    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .generalXcmConfig)
    }

    func asyncWaitGameResultsFallbackURL() -> CompoundOperationWrapper<URL> {
        asyncWaitForRemoteConfigValues(for: .gameResultsFallbackURL)
    }

    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .w3sMerchants)
    }

    func asyncWaitCollectiblesFallbackURL() -> CompoundOperationWrapper<URL> {
        asyncWaitForRemoteConfigValues(for: .collectiblesFallbackURL)
    }

    func syncedWeb3SummitGateMode() -> String? {
        let value = remoteConfig[.w3sGateMode].stringValue
        return value.isEmpty ? nil : value
    }

    func syncedWeb3SummitStartGate() -> String? {
        let value = remoteConfig[.w3sStartGate].stringValue
        return value.isEmpty ? nil : value
    }

    func syncedCollectiblesEnabled() -> Bool {
        remoteConfig[.collectiblesEnabled].boolValue
    }

    func syncedAppConfig() -> RemoteAppConfig {
        RemoteAppConfig(
            identityBackendUrl: url(for: .identityBackendUrl),
            ipfsGatewayUrl: url(for: .ipfsGatewayUrl),
            gameDashboardUrl: url(for: .gameDashboardUrl),
            dotNsResolver: dotNsResolverAddress(),
            web3SummitDotNsUrl: web3SummitDotNsUrl(),
            web3SummitContractAddress: web3SummitContractAddress()
        )
    }

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig {
        syncedAppConfig()
    }
}

private extension FirebaseApplicationService {
    // MARK: Private methods

    private func configurationRemoteConfigSettings() {
        let remoteConfigSettings = RemoteConfigSettings()
        remoteConfigSettings.minimumFetchInterval = .zero
        remoteConfig.configSettings = remoteConfigSettings
    }

    private func handleRemoteConfigStatus(_ status: RemoteConfigFetchAndActivateStatus) {
        defer {
            delegate?.remoteConfig(didFinishLoading: .success(()))
        }
        switch status {
        case .successFetchedFromRemote:
            logger.info("RemoteConfig fetched from remote and activated")
        case .successUsingPreFetchedData:
            logger.info("RemoteConfig activated using pre-fetched data")
        case .error:
            logger.error("Error during RemoteConfig activation")
        @unknown default:
            logger.error("Unknown status during RemoteConfig activation")
        }

        let appVersion = remoteConfig[.latestAppVersion].stringValue
        guard !appVersion.isEmpty else {
            logger.error("App version not found in RemoteConfig")
            delegate?.remoteConfig(appVersionDidChange: .failure(RemoteConfigError.versionNotFound))
            return
        }
        logger.info("Fetched latest app version: \(appVersion)")
        delegate?.remoteConfig(appVersionDidChange: .success(appVersion))
    }

    func nonEmptyString(for key: String) -> String? {
        let value = remoteConfig[key].stringValue
        return value.isEmpty ? nil : value
    }

    func url(for key: String) -> URL? {
        guard let value = nonEmptyString(for: key) else { return nil }
        return URL(string: value)
    }

    func dotNsResolverAddress() -> String? {
        let json = remoteConfig[.dotNsResolver].jsonValue as? [String: String]
        return json?["resolverContractAddress"]
    }

    func web3SummitConfigJson() -> [String: String]? {
        remoteConfig[.web3SummitConfig].jsonValue as? [String: String]
    }

    func web3SummitDotNsUrl() -> URL? {
        guard let value = web3SummitConfigJson()?["dotNsUrl"], !value.isEmpty else { return nil }
        return URL(string: value)
    }

    func web3SummitContractAddress() -> String? {
        guard let value = web3SummitConfigJson()?["contractAddress"], !value.isEmpty else { return nil }
        return value
    }

    func asyncWaitForRemoteConfigValues<T: Decodable>(for key: String) -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper(targetOperation: AsyncClosureOperation<T>(
            operationClosure: { [weak self] closure in
                guard let self else {
                    return
                }

                let data = remoteConfig[key].dataValue
                do {
                    let models = try JSONDecoder().decode(T.self, from: data)

                    closure(.success(models))
                } catch {
                    closure(.failure(error))
                }
            },
            cancelationClosure: {}
        ))
    }
}

// MARK: - Constants

private extension String {
    static let latestAppVersion = "latest_ios_version"
    static func chains() -> String {
        #if UNSTABLE
            "chains_v2"
        #elseif NIGHTLY
            "chains_v2"
        #else
            "chains"
        #endif
    }

    static let xcmTransfers = "cross_chain_transfers"
    static let generalXcmConfig = "xcm_general_config"
    static let gameResultsFallbackURL = "game_results_fallback_url"
    static let w3sMerchants = "w3s_merchants"
    static let collectiblesFallbackURL = "collectibles_fallback_url"
    static let collectiblesEnabled = "collectibles_enabled"
    static let w3sGateMode = "w3s_gate_mode"
    static let w3sStartGate = "w3s_start_gate"
    static let identityBackendUrl = "identity_backend_url"
    static let ipfsGatewayUrl = "ipfs_gateway_url"
    static let gameDashboardUrl = "game_dashboard_url"
    static let dotNsResolver = "dot_ns_config"
    static let web3SummitConfig = "web3summit_config"
}
