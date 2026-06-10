import FoundationExt
import Products
import UIKit
import WebKit

final class SPAViewController: UIViewController, ViewHolder {
    typealias RootViewType = SPAViewLayout

    let presenter: SPAPresenterProtocol
    let configuration: SPAConfiguration

    private let schemeHandlerProxy: SchemeHandlerProxy
    private let logger: LoggerProtocol

    private var titleObservation: NSKeyValueObservation?

    init(
        presenter: SPAPresenterProtocol,
        configuration: SPAConfiguration,
        schemeHandlerProxy: SchemeHandlerProxy,
        logger: LoggerProtocol
    ) {
        self.presenter = presenter
        self.configuration = configuration
        self.schemeHandlerProxy = schemeHandlerProxy
        self.logger = logger
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let webViewConfiguration = WKWebViewConfiguration()

        webViewConfiguration.allowsInlineMediaPlayback = true
        webViewConfiguration.mediaTypesRequiringUserActionForPlayback = []

        webViewConfiguration.setURLSchemeHandler(
            schemeHandlerProxy,
            forURLScheme: ProductScriptSchemeHandler.scheme
        )
        view = SPAViewLayout(webViewConfiguration: webViewConfiguration)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupTitleObservation()
        setupJSEngine()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        setupWebViewLayout()
    }

    deinit {
        titleObservation?.invalidate()
    }
}

// MARK: - Private

private extension SPAViewController {
    func setupWebView() {
        rootView.webView.scrollView.pinchGestureRecognizer?.isEnabled = false
    }

    func setupJSEngine() {
        let navigationHandler = DotNsNavigationDecisionHandler(baseHost: configuration.page.host)

        let engine = SPAJSEngine(
            webView: rootView.webView,
            navigationDecisionHandler: navigationHandler,
            logger: logger
        )

        engine.onNavigationIntercepted = { [weak self] url in
            self?.presenter.didInterceptNavigation(to: url)
        }

        presenter.setup(engine: engine)
    }

    func setupNavigationBar() {
        if configuration.isRootScreen {
            setTitle(String(localized: .tabBrowse))
        }

        if configuration.showMoreButton {
            setupMoreButton()
        }
    }

    func setupMoreButton() {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: self,
            action: #selector(onMoreTapped)
        )
        button.tintColor = .fgPrimary
        navigationItem.rightBarButtonItem = button
    }

    func setupTitleObservation() {
        if configuration.title == nil, !configuration.isRootScreen {
            titleObservation = rootView.webView.observe(\.title, options: .new) { [weak self] webView, _ in
                guard let title = webView.title, !title.isEmpty else { return }

                self?.presenter.didUpdateWebViewTitle(title)
            }
        }
    }

    func setupWebViewLayout() {
        if configuration.isRootScreen {
            rootView.setupRootLayout()
        } else {
            rootView.setupDefaultLayout()
        }
    }

    // MARK: - Actions

    @objc func onMoreTapped() {
        presenter.didTapMoreButton()
    }
}

// MARK: - SPAViewProtocol

extension SPAViewController: SPAViewProtocol {
    func navigate(to url: URL) {
        rootView.webView.load(URLRequest(url: url))
    }

    func updateTitle(_ title: String) {
        navigationItem.title = title
    }

    func reload() {
        rootView.webView.reload()
    }

    func showLoading() {
        rootView.activityIndicatorView.startAnimating()
    }

    func hideLoading() {
        rootView.activityIndicatorView.stopAnimating()
    }
}

// MARK: - RootScreen

extension SPAViewController: RootScreen {}
