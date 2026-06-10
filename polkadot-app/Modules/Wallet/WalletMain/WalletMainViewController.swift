import SwiftUI
import PolkadotUI

final class WalletMainViewController: UIHostingController<WalletView>, RootScreen {
    let presenter: WalletMainPresenterProtocol

    private var assetDetailsScene: AssetDetailsScene
    private var identityDetailsScene: IdentityDetailsScene

    @available(iOS, obsoleted: 26)
    private var walletLeftBarButtonItem: UIBarButtonItem?

    private let titleLabel: PolkadotUI.Label = .create { view in
        view.typography = .headlineSmall
        view.textColor = .fgPrimary
    }

    init(
        presenter: WalletMainPresenterProtocol,
        assetDetailsScene: AssetDetailsScene,
        identityDetailsScene: IdentityDetailsScene
    ) {
        self.presenter = presenter
        self.assetDetailsScene = assetDetailsScene
        self.identityDetailsScene = identityDetailsScene
        super.init(rootView: WalletView())
    }

    @available(*, unavailable)
    @MainActor @preconcurrency dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .bgSurfaceMain
        if #available(iOS 26.0, *) {
            navigationItem.titleView = titleLabel
        } else {
            walletLeftBarButtonItem = UIBarButtonItem(customView: titleLabel)
            navigationItem.leftBarButtonItem = walletLeftBarButtonItem
        }

        setTitle(String(localized: .walletMainTitle))

        setScanButton()
        assetDetailsScene.attachNavigationHost(self)
        identityDetailsScene.attachNavigationHost(self)
        setupHandlers()
        presenter.setup()
    }

    private func setupHandlers() {
        rootView.viewModel.identityDetailsViewModel = identityDetailsScene.viewModel
        rootView.viewModel.assetDetailsViewModel = assetDetailsScene.viewModel
        rootView.viewModel.onUsername = { [weak self] in
            self?.showIdentityDetailsOverlay()
        }

        rootView.viewModel.onBalance = { [weak self] in
            self?.showAssetDetailsOverlay()
        }

        rootView.viewModel.onCollapse = { [weak self] in
            self?.collapseExpandedSection()
        }

        rootView.viewModel.onCollectibles = { [weak self] in
            self?.showCollectiblesOverlay()
        }

        rootView.viewModel.onViewCollectibles = { [weak presenter] in
            presenter?.showCollectibles()
        }
    }

    private func setShareButton() {
        let item = UIBarButtonItem(
            image: .iconShareWallet,
            style: .plain,
            target: self,
            action: #selector(didTapShare)
        )
        navigationItem.setRightBarButton(item, animated: true)
    }

    private func resetRightButton() {
        navigationItem.setRightBarButton(nil, animated: true)
    }

    private func setScanButton() {
        let item = UIBarButtonItem(
            image: .scanBarButton,
            style: .plain,
            target: self,
            action: #selector(didTapScan)
        )
        navigationItem.setRightBarButton(item, animated: true)
    }

    private func resetOverlayCloseButton() {
        navigationItem.setLeftBarButton(nil, animated: true)
    }

    private func setOverlayCloseButton() {
        let item = UIBarButtonItem(
            image: .buttonClose.withRenderingMode(.alwaysTemplate),
            style: .plain,
            target: self,
            action: #selector(collapseExpandedSection)
        )
        navigationItem.setLeftBarButton(item, animated: true)
    }
}

extension WalletMainViewController: WalletMainViewProtocol {
    func didReceive(isCollectiblesAvailable: Bool) {
        rootView.viewModel.isCollectiblesAvailable = isCollectiblesAvailable
    }

    @objc
    func didTapScan() {
        presenter.scanQR()
    }

    @objc
    func didTapShare() {
        identityDetailsScene.share()
    }

    @objc
    func collapseExpandedSection() {
        rootView.viewModel.expandedSection = .none
        resetOverlayCloseButton()
        setScanButton()
        setTitle(String(localized: .walletMainTitle))
    }

    private func showAssetDetailsOverlay() {
        rootView.viewModel.expandedSection = .assetDetails
        setOverlayCloseButton()
        setScanButton()
        setTitleCenter(String(localized: .walletMainBalanceCard))
    }

    private func showIdentityDetailsOverlay() {
        rootView.viewModel.expandedSection = .identityDetails
        setOverlayCloseButton()
        setShareButton()
        setTitleCenter(String(localized: .walletMainIdCard))
    }

    private func showCollectiblesOverlay() {
        rootView.viewModel.expandedSection = .collectiblesDetails
        setOverlayCloseButton()
        resetRightButton()
        setTitleCenter(nil)
    }

    func setTitle(_ title: String) {
        navigationItem.style = .browser
        if #unavailable(iOS 26.0) {
            navigationItem.title = nil
            navigationItem.leftBarButtonItem = walletLeftBarButtonItem
        }
        titleLabel.text = title
        titleLabel.typography = .headlineSmall
        titleLabel.sizeToFit()
    }

    func setTitleCenter(_ title: String?) {
        navigationItem.style = .navigator
        guard #available(iOS 26, *) else {
            navigationItem.title = title
            return
        }
        titleLabel.text = title
        titleLabel.typography = .titleLarge
        titleLabel.sizeToFit()
    }
}
