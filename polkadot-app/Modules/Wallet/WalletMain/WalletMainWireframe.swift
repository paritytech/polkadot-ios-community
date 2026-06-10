import UIKit

final class WalletMainWireframe: WalletMainWireframeProtocol {
    private let personDataStore: DetermineStatePersonDataStore

    init(personDataStore: DetermineStatePersonDataStore) {
        self.personDataStore = personDataStore
    }

    func showQRScanner(
        view: WalletMainViewProtocol?,
        delegate: WalletQRScanDelegate
    ) {
        guard
            let scanView = WalletQRScanViewFactory.createView(for: delegate)
        else {
            return
        }

        let navigationController = AppNavigationController(rootViewController: scanView.controller)

        navigationController.barSettings = .init(
            style: NavigationBarStyle(
                backgroundColor: nil,
                shadow: nil,
                shadowColor: nil,
                tintColor: .white100,
                backImage: nil,
                backgroundEffect: nil,
                titleAttributes: nil,
                largeTitleAttributes: nil
            ),
            shouldSetCloseButton: true
        )

        navigationController.modalPresentationStyle = .fullScreen

        view?.controller.present(navigationController, animated: true, completion: nil)
    }

    func showCollectibles(from view: WalletMainViewProtocol?, url: URL) {
        guard let collectiblesView = CollectiblesViewFactory.createView(
            url: url,
            personDataStore: personDataStore
        ) else {
            return
        }

        let nav = AppNavigationController(rootViewController: collectiblesView.controller)
        nav.modalPresentationStyle = .fullScreen

        view?.controller.present(nav, animated: true)
    }

    func dismissPresented(
        from view: WalletMainViewProtocol?,
        completion: @escaping () -> Void
    ) {
        guard let presented = view?.controller.presentedViewController else {
            completion()
            return
        }
        presented.dismiss(animated: true, completion: completion)
    }
}
