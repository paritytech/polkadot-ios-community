import SnapKit
import UIKit
import WebKit
import PolkadotUI

final class SPAViewLayout: UIView {
    let webView: WKWebView

    let activityIndicatorView = ActivityIndicatorView()

    init(webViewConfiguration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        super.init(frame: .zero)

        backgroundColor = .bgSurfaceMain
        webView.isOpaque = false
        webView.backgroundColor = .bgSurfaceMain
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupRootLayout() {
        addSubview(webView)
        webView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        setupActivityIndicatorLayout()
        webView.scrollView.contentInsetAdjustmentBehavior = .scrollableAxes
    }

    func setupDefaultLayout() {
        addSubview(webView)
        webView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalToSuperview()
        }

        setupActivityIndicatorLayout()
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    private func setupActivityIndicatorLayout() {
        addSubview(activityIndicatorView)
        activityIndicatorView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
