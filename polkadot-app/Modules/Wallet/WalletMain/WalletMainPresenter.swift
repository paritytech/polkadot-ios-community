import Foundation
import UIKit.UIApplication

final class WalletMainPresenter {
    weak var view: WalletMainViewProtocol?
    let wireframe: WalletMainWireframeProtocol
    let dsfinvkRouter: W3sDsfinvkRouting

    private let collectiblesURLProvider: CollectiblesURLProviding

    private var collectiblesURL: URL?
    private var resolutionTask: Task<Void, Never>?

    init(
        wireframe: WalletMainWireframeProtocol,
        dsfinvkRouter: W3sDsfinvkRouting,
        collectiblesURLProvider: CollectiblesURLProviding
    ) {
        self.wireframe = wireframe
        self.dsfinvkRouter = dsfinvkRouter
        self.collectiblesURLProvider = collectiblesURLProvider
    }

    deinit {
        resolutionTask?.cancel()
    }
}

extension WalletMainPresenter: WalletMainPresenterProtocol {
    func setup() {
        guard resolutionTask == nil else { return }

        resolutionTask = Task { [weak self, collectiblesURLProvider] in
            let url = await collectiblesURLProvider.resolveURL()
            await self?.applyCollectiblesURL(url)
        }
    }

    func scanQR() {
        wireframe.showQRScanner(view: view, delegate: self)
    }

    func showCollectibles() {
        guard let url = collectiblesURL else { return }
        wireframe.showCollectibles(from: view, url: url)
    }
}

extension WalletMainPresenter: WalletQRScanDelegate {
    func walletQRScanDidReceiveURL(_ url: URL) {
        // Dismiss the scanner first; otherwise the launcher modal stacks on top of it.
        wireframe.dismissPresented(from: view) {
            UIApplication.shared.open(url)
        }
    }

    func walletQRScanDidReceiveDsfinvkReceipt(_ receipt: W3sDsfinvkReceipt) {
        wireframe.dismissPresented(from: view) { [dsfinvkRouter] in
            Task { @MainActor in
                await dsfinvkRouter.route(receipt)
            }
        }
    }
}

private extension WalletMainPresenter {
    @MainActor
    func applyCollectiblesURL(_ url: URL?) {
        collectiblesURL = url
        view?.didReceive(isCollectiblesAvailable: url != nil)
    }
}
