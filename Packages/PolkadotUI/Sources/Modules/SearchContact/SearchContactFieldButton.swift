import DesignSystem
import UIKit
internal import SnapKit
internal import UIKit_iOS

public final class SearchContactFieldButton: UIControl {
    private let iconImageView: UIImageView = create {
        $0.image = UIImage(resource: .search18).withRenderingMode(.alwaysTemplate)
        $0.tintColor = .fgSecondary
        $0.snp.makeConstraints {
            $0.width.height.equalTo(18)
        }
    }

    private let label: Label = create {
        $0.style = .body14Regular()
        $0.textColor = .fgDisabled
        $0.text = String(localized: .searchContactFieldPlaceholder)
    }

    public var onTap: (() -> Void)?

    public init() {
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        addSubview(iconImageView)
        addSubview(label)

        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.8
        backgroundColor = .bgSurfaceNested
        applyLayerColors()

        iconImageView.isUserInteractionEnabled = false
        label.isUserInteractionEnabled = false

        snp.makeConstraints {
            $0.height.equalTo(48)
        }

        iconImageView.snp.makeConstraints {
            $0.leading.equalToSuperview().inset(12)
            $0.centerY.equalToSuperview()
        }

        label.snp.makeConstraints {
            $0.leading.equalTo(iconImageView.snp.trailing).offset(8)
            $0.trailing.equalToSuperview().inset(16)
            $0.centerY.equalToSuperview()
        }

        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = String(localized: .searchContactFieldPlaceholder)

        registerForTraitChanges([DSThemeTrait.self]) { (view: SearchContactFieldButton, _) in
            view.applyLayerColors()
        }
    }

    @objc private func didTap() {
        onTap?()
    }
}

private extension SearchContactFieldButton {
    func applyLayerColors() {
        layer.borderColor = UIColor.strokePrimary.resolvedColor(with: traitCollection).cgColor
    }
}
