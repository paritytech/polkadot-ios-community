import DesignSystem
import PolkadotUI
import SnapKit
import UIKit

final class ScanPanelViewLayout: UIView {
    let searchRow = DSSearchRowView()

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

        scannerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(searchRow.snp.top)
        }
    }
}
