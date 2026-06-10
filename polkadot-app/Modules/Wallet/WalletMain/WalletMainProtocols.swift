import Foundation
import UIKitExt

protocol WalletMainViewProtocol: ControllerBackedProtocol {
    func didReceive(isCollectiblesAvailable: Bool)
}

protocol WalletMainPresenterProtocol: AnyObject {
    func setup()
    func scanQR()
    func showCollectibles()
}

protocol WalletMainWireframeProtocol: AnyObject {
    func showQRScanner(
        view: WalletMainViewProtocol?,
        delegate: WalletQRScanDelegate
    )

    func showCollectibles(from view: WalletMainViewProtocol?, url: URL)

    func dismissPresented(
        from view: WalletMainViewProtocol?,
        completion: @escaping () -> Void
    )
}
