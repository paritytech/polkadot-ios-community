import Foundation

#if TESTNET_FEATURE
    import Sentry
#endif

protocol IssueMonitoringServicing {
    func setup()
}

final class IssueMonitoringService: IssueMonitoringServicing {
    func setup() {
        #if TESTNET_FEATURE
            // DSN is injected at build time (env-vars.sh → SENTRY_DSN). When it is
            // not configured, issue monitoring is simply disabled.
            let dsn = CIKeys.sentryDSN
            guard !dsn.isEmpty else { return }

            SentrySDK.start { options in
                options.dsn = dsn

                // Adds IP for users.
                // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
                options.sendDefaultPii = false

                // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
                // We recommend adjusting this value in production.
                options.tracesSampleRate = 0
            }
        #endif
    }
}
