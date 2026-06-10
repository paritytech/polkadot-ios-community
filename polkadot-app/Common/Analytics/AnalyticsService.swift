import Foundation

#if TESTNET_FEATURE
    import PostHog
#endif

protocol AnalyticsServicing {
    func setup()
}

final class AnalyticsService: AnalyticsServicing {
    private let anonymousDeviceIDProvider: AnonymousDeviceIDProviding

    init(anonymousDeviceIDProvider: AnonymousDeviceIDProviding = AnonymousDeviceIDProvider()) {
        self.anonymousDeviceIDProvider = anonymousDeviceIDProvider
    }

    func setup() {
        #if TESTNET_FEATURE
            // The API key is injected at build time (env-vars.sh → POSTHOG_API_KEY).
            // When it is not configured, analytics is simply disabled.
            guard !AppConfig.Analytics.posthogAPIKey.isEmpty else { return }

            let config = PostHogConfig(
                apiKey: AppConfig.Analytics.posthogAPIKey,
                host: AppConfig.Analytics.posthogHost
            )
            config.captureApplicationLifecycleEvents = true
            config.captureScreenViews = true
            PostHogSDK.shared.setup(config)
            logIdentity()
        #endif
    }
}

private extension AnalyticsService {
    func logIdentity() {
        #if TESTNET_FEATURE
            let identityID = anonymousDeviceIDProvider.getOrCreate()
            PostHogSDK.shared.identify(identityID)
        #endif
    }
}
