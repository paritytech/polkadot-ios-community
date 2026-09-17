import DesignSystem
import PolkadotUI
import SnapKit
import UIKit

final class ScanPanelViewLayout: UIView {
    private enum Constants {
        static let compactCameraWidthRatio: CGFloat = 0.25
    }

    let searchRow = DSSearchRowView()

    /// Stands in for the camera while `AVCaptureSession` configures and starts, which takes
    /// roughly a second. It sits behind the preview, which fades in over it.
    private let placeholderView: UIView = {
        let view = UIView()
        view.backgroundColor = .bgSurfaceNested
        view.layer.cornerRadius = DSRadii.large
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var cameraTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(cameraTapped))
        recognizer.isEnabled = false
        return recognizer
    }()

    private var fullHorizontalConstraints: [Constraint] = []
    private var compactHorizontalConstraints: [Constraint] = []

    var onCameraTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(searchRow)

        searchRow.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(DSSpacings.mediumIncreased)
            make.bottom.equalToSuperview().inset(DSSpacings.small)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupScannerView(_ scannerView: UIView) {
        insertSubview(scannerView, at: 0)
        insertSubview(placeholderView, belowSubview: scannerView)

        placeholderView.snp.makeConstraints { make in
            make.edges.equalTo(scannerView)
        }

        scannerView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(DSSpacings.mediumIncreased)
            make.bottom.equalTo(searchRow.snp.top).offset(-DSSpacings.small)

            fullHorizontalConstraints = [
                make.leading.equalToSuperview().offset(DSSpacings.mediumIncreased).constraint,
                make.trailing.equalToSuperview().inset(DSSpacings.mediumIncreased).constraint
            ]

            compactHorizontalConstraints = [
                make.centerX.equalToSuperview().constraint,
                make.width.equalToSuperview().multipliedBy(Constants.compactCameraWidthRatio).constraint
            ]
        }

        compactHorizontalConstraints.forEach { $0.deactivate() }

        scannerView.addGestureRecognizer(cameraTapRecognizer)
    }

    /// The camera shrinks to a centred square above the field while the field is focused.
    func setCameraCompact(_ compact: Bool) {
        if compact {
            fullHorizontalConstraints.forEach { $0.deactivate() }
            compactHorizontalConstraints.forEach { $0.activate() }
        } else {
            compactHorizontalConstraints.forEach { $0.deactivate() }
            fullHorizontalConstraints.forEach { $0.activate() }
        }

        cameraTapRecognizer.isEnabled = compact
    }
}

private extension ScanPanelViewLayout {
    @objc func cameraTapped() {
        onCameraTapped?()
    }
}
