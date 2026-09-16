import DesignSystem
import PolkadotUI
import SnapKit
import UIKit

final class ScanPanelViewLayout: UIView {
    let searchButton = SearchContactFieldButton()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(searchButton)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupScannerView(_ scannerView: UIView) {
        insertSubview(scannerView, at: 0)

        scannerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        searchButton.snp.makeConstraints { make in
            make.top.equalTo(scannerView.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(DSSpacings.mediumIncreased)
            make.bottom.equalToSuperview().inset(DSSpacings.small)
        }
    }
}
