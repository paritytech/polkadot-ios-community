@testable import polkadot_app
import Foundation
import Testing

@MainActor
struct MainTabBarInstallationStatusTests {
    @Test("A phone replaced while on the dashboard hands over to the root once")
    func replacedPhoneLeavesOnce() {
        let wireframe = TabBarWireframeSpy()
        let presenter = MainTabBarPresenter(
            interactor: IdleTabBarInteractor(),
            wireframe: wireframe,
            chipViewModelFactory: SPATabChipViewModelFactory(flowStateProvider: SPAFlowStateProvider())
        )
        let newPhone = ActiveInstallation(
            installationId: Data(repeating: 0x02, count: 32),
            deviceModel: "iPhone 17 Pro",
            operatingSystem: "iOS 26.1",
            activatedAt: 1
        )

        presenter.didReceiveInstallationStatus(.unknown)
        presenter.didReceiveInstallationStatus(.active)
        #expect(wireframe.leaveCount == 0)

        presenter.didReceiveInstallationStatus(.inactive(newPhone))
        presenter.didReceiveInstallationStatus(.unreadable)

        #expect(wireframe.leaveCount == 1)
    }
}

private final class IdleTabBarInteractor: MainTabBarInteractorInputProtocol {
    func setup() {}
}

@MainActor
private final class TabBarWireframeSpy: MainTabBarWireframeProtocol {
    private(set) var leaveCount = 0

    func leaveReplacedInstallation() {
        leaveCount += 1
    }

    func showPolkadotSignIn(with _: URL, view _: MainTabBarViewProtocol?) {}
    func showPaymentsSetupNotice(isVisible _: Bool) {}
    #if FEATURE_INPUT
        func openChat(_: ChatOpenModel) {}
    #else
        func showSearchContact(from _: MainTabBarViewProtocol?) {}
    #endif
    func showConnectionStatus(_: ConnectionStatusSheetViewModel, from _: MainTabBarViewProtocol?) {}
    func showSettings(from _: MainTabBarViewProtocol?) {}
    func showDeviceTransferRequest(_: DeviceTransferRequest, from _: MainTabBarViewProtocol?) {}
}
