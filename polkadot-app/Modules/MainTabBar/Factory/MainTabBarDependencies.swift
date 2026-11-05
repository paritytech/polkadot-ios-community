import Foundation

/// What the root hands to every dashboard it builds.
struct MainTabBarDependencies {
    let userNotificationService: UserNotificationServicing
    weak var foregroundVisibilityReporter: PushForegroundVisibilityReporting?
    let deepLinkHandling: DeferredLinkHandling
    let flowStateProvider: any SPAFlowStateProviding
}
