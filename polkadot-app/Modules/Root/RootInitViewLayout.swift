import UIKit
import SnapKit
import PolkadotUI
import UIKit_iOS

protocol RootInitViewLayoutDelegate: AnyObject {
    func didTapRetry()
}

final class RootInitViewLayout: UIView {
    weak var delegate: RootInitViewLayoutDelegate?

    private let logoImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = .fgPrimary
        view.image = .polkadotLogoLoading.withRenderingMode(.alwaysTemplate)
        return view
    }()

    private let issueView: TopBottomLabelView = {
        let view = TopBottomLabelView()
        view.topLabel.style = .title16SemiBold()
        view.topLabel.textColor = UIColor.fgPrimary
        view.topLabel.textAlignment = .center
        view.topLabel.numberOfLines = 0
        view.bottomLabel.style = .body14Regular()
        view.bottomLabel.textColor = UIColor.fgTertiary
        view.bottomLabel.textAlignment = .center
        view.bottomLabel.numberOfLines = 0
        view.spacing = 4
        view.isHidden = true
        return view
    }()

    private let stackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 16
        return view
    }()

    private let retryButton: RoundedButton = create {
        $0.applySecondaryStyle()
        $0.setTitle(.init(localized: .rootInitFailureAction))
        $0.setHidden(true)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .bgSurfaceMain
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension RootInitViewLayout {
    enum ViewModel {
        struct Issue {
            let title: String
            let subtitle: String
        }

        case loading(hint: String?)
        case failed(Issue)
    }

    func bind(viewModel: ViewModel) {
        switch viewModel {
        case let .loading(hint):
            guard let hint else {
                animateIssueDismissal()
                return
            }

            showIssue(title: nil, subtitle: hint)
            retryButton.setHidden(true)
        case let .failed(issue):
            showIssue(title: issue.title, subtitle: issue.subtitle)
            retryButton.setHidden(false)
        }
    }
}

private extension RootInitViewLayout {
    func setupLayout() {
        addSubview(stackView)
        stackView.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.greaterThanOrEqualToSuperview().offset(16)
            $0.trailing.lessThanOrEqualToSuperview().offset(-16)
        }

        stackView.addArrangedSubview(logoImageView)
        stackView.addArrangedSubview(issueView)
        stackView.addArrangedSubview(retryButton)

        logoImageView.snp.makeConstraints {
            $0.size.equalTo(64)
        }

        retryButton.snp.makeConstraints {
            $0.height.equalTo(UIConstants.actionHeight)
        }

        retryButton.addTarget(self, action: #selector(didTapRetry), for: .touchUpInside)
    }

    @objc
    func didTapRetry() {
        delegate?.didTapRetry()
    }

    func showIssue(title: String?, subtitle: String) {
        issueView.topLabel.text = title
        issueView.topLabel.setHidden(title == nil)
        issueView.bottomLabel.text = subtitle

        animateIssueAppearance()
    }

    func animateIssueAppearance() {
        guard issueView.isHidden else { return }
        issueView.alpha = 0

        UIView.animate(springDuration: 0.3, bounce: 0) { [weak self] in
            self?.issueView.setHidden(false)
            self?.layoutIfNeeded()
        }

        UIView.animate(springDuration: 0.3, bounce: 0, delay: 0.25) { [issueView] in
            issueView.alpha = 1
        }
    }

    func animateIssueDismissal() {
        guard !issueView.isHidden else { return }

        UIView.animate(springDuration: 0.35, bounce: 0) { [weak self] in
            self?.issueView.alpha = 0
            self?.issueView.setHidden(true)
            self?.retryButton.setHidden(true)
            self?.layoutIfNeeded()
        }
    }
}
