import DesignSystem
import PolkadotUI
import SnapKit
import UIKit

/// Scan panel without the in-panel search field: a camera above a button that opens full-screen
/// search. `EmbeddedQRScannerViewLayout` is a bare preview now, so the insets and the startup
/// placeholder live here.
final class ScanPanelPlainViewLayout: UIView {
    private static let cameraSideInset = DSSpacings.mediumIncreased
    private static let contentTopInset = DSTabBarStyle.centerGrabberHeight + DSSpacings.mediumIncreased
    private static let gapBelowContent = DSSpacings.small
    private static let searchButtonHeight: CGFloat = 48
    private static let searchButtonBottomInset = DSSpacings.small

    let searchButton = SearchContactFieldButton()

    /// Stands in for the camera while `AVCaptureSession` configures and starts, which takes
    /// roughly a second. It sits behind the preview, which fades in over it.
    private let placeholderView: UIView = {
        let view = UIView()
        view.backgroundColor = .bgSurfaceNested
        view.layer.cornerRadius = DSRadii.large
        view.layer.masksToBounds = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(searchButton)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Height the panel declares at `width`, grabber clearance included. The tab bar reads it before the
    /// panel lays out, so it is computed from the constants the constraints use. The camera is square, as
    /// `EmbeddedQRScannerViewLayout` pins it.
    static func declaredHeight(forWidth width: CGFloat) -> CGFloat {
        let cameraSide = width - 2 * cameraSideInset
        return contentTopInset + cameraSide + gapBelowContent + searchButtonHeight + searchButtonBottomInset
    }

    func setupScannerView(_ scannerView: UIView) {
        insertSubview(placeholderView, at: 0)
        insertSubview(scannerView, at: 1)

        scannerView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Self.contentTopInset)
            make.leading.trailing.equalToSuperview().inset(Self.cameraSideInset)
        }

        placeholderView.snp.makeConstraints { make in
            make.edges.equalTo(scannerView)
        }

        searchButton.snp.makeConstraints { make in
            make.top.equalTo(scannerView.snp.bottom).offset(Self.gapBelowContent)
            make.leading.trailing.equalToSuperview().inset(Self.cameraSideInset)
            make.height.equalTo(Self.searchButtonHeight)
            make.bottom.equalToSuperview().inset(Self.searchButtonBottomInset)
        }
    }
}
