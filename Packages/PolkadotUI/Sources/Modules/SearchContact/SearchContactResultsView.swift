import DesignSystem
import UIKit
internal import SnapKit
internal import UIKit_iOS

public final class SearchContactResultsView: UIView {
    private let scrollView = UIScrollView()
    private let scrollContainer = UIView()
    private let stackView = UIStackView()

    private let noResultsLabel: Label = create {
        $0.numberOfLines = 0
        $0.textAlignment = .center
    }

    private let loadingView = SearchContactLoadingView()

    private let fadeMask = CAGradientLayer()

    private let separatorConfiguration = SeparatorContentConfiguration(
        color: UIColor.strokePrimary,
        height: Constants.separatorHeight,
        insets: NSDirectionalEdgeInsets(top: 0, leading: 64, bottom: 0, trailing: 16)
    )

    public var selectionHandler: ((String) -> Void)?

    private var statusFloorConstraint: Constraint?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        updateFadeMask()
    }

    public func bind(status: StatusViewModel) {
        updateStatusFloor(for: status)
        noResultsLabel.attributedText = status.message
        noResultsLabel.setHidden(status.message == nil)
        loadingView.bind(text: status.loaderText)
        loadingView.setLoading(status.showsLoader)
    }

    public func bind(viewModel: ViewModel) {
        bind(status: viewModel.status)
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for section in viewModel.sections {
            addSectionTopInset()
            addSectionViews(for: section)
        }
        updateFadeMask()
    }
}

public extension SearchContactResultsView {
    /// `message` is centred text shown instead of rows: the no-recents hint or the failure reason.
    struct StatusViewModel {
        public let message: NSAttributedString?
        public let showsLoader: Bool
        public let loaderText: String?

        public init(
            message: NSAttributedString? = nil,
            showsLoader: Bool = false,
            loaderText: String? = nil
        ) {
            self.message = message
            self.showsLoader = showsLoader
            self.loaderText = loaderText
        }
    }

    struct ViewModel {
        public struct Section {
            public let id: String
            public let title: String?
            public let rows: [IdentifiableContentConfiguration<String, SearchContactListConfiguration>]

            public init(
                id: String,
                title: String?,
                rows: [IdentifiableContentConfiguration<String, SearchContactListConfiguration>]
            ) {
                self.id = id
                self.title = title
                self.rows = rows
            }
        }

        let sections: [Section]
        let status: StatusViewModel

        public init(sections: [Section], status: StatusViewModel) {
            self.sections = sections
            self.status = status
        }
    }
}

private extension SearchContactResultsView {
    enum Constants {
        static let statusHeight: CGFloat = 120
        static let sectionTopInset: CGFloat = 16
        static let interItemSpacing: CGFloat = 8
        static let separatorHeight: CGFloat = 1
        static let fadeHeight: CGFloat = 16
    }

    func setupViews() {
        backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.keyboardDismissMode = .none

        noResultsLabel.setHidden(true)
        loadingView.setHidden(true)

        stackView.axis = .vertical
        stackView.spacing = Constants.interItemSpacing
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true

        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        addSubview(scrollContainer)
        scrollContainer.addSubview(scrollView)
        scrollView.addSubview(stackView)
        addSubview(noResultsLabel)
        addSubview(loadingView)

        fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]

        scrollContainer.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            // Yields when the host collapses the view to zero height.
            make.bottom.equalToSuperview().priority(.high)
        }

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(stackView).priority(.low)
            statusFloorConstraint = make.height.greaterThanOrEqualTo(Constants.statusHeight)
                .priority(.high).constraint
        }
        statusFloorConstraint?.deactivate()

        stackView.snp.makeConstraints { make in
            make.top.bottom.equalTo(scrollView.contentLayoutGuide)
            make.leading.trailing.equalTo(scrollView.frameLayoutGuide)
        }

        noResultsLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(24)
        }

        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    /// Updates the fade gradient mask on resize and when content changes. The mask sits on the
    /// non-scrolling container so the gradient stays at the bottom edge while rows scroll under it.
    /// Only an overflowing list is masked, so one that fits keeps its last row fully visible.
    func updateFadeMask() {
        scrollView.layoutIfNeeded()

        let bounds = scrollContainer.bounds
        let overflows = scrollView.contentSize.height > bounds.height + 0.5
        guard overflows, bounds.height > Constants.fadeHeight else {
            scrollContainer.layer.mask = nil
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        let fadeStart = (bounds.height - Constants.fadeHeight) / bounds.height
        fadeMask.locations = [0, NSNumber(value: fadeStart), 1]
        scrollContainer.layer.mask = fadeMask
        CATransaction.commit()
    }

    func addSectionTopInset() {
        if let lastView = stackView.arrangedSubviews.last {
            stackView.setCustomSpacing(Constants.sectionTopInset, after: lastView)
            return
        }

        let topSpacer = UIView()
        topSpacer.snp.makeConstraints { $0.height.equalTo(Constants.sectionTopInset) }
        stackView.addArrangedSubview(topSpacer)
    }

    func addSectionViews(for section: ViewModel.Section) {
        if let title = section.title {
            let headerView = SearchContactSectionHeaderConfiguration(title: title).makeContentView()
            stackView.addArrangedSubview(headerView)
        }

        for (offset, item) in section.rows.enumerated() {
            let rowContainer = RowTapContainer(contentView: item.configuration.makeContentView())
            rowContainer.onTap = { [weak self] in
                self?.selectionHandler?(item.id)
            }
            stackView.addArrangedSubview(rowContainer)

            if offset < section.rows.count - 1 {
                stackView.addArrangedSubview(separatorConfiguration.makeContentView())
            }
        }
    }

    /// A status replaces the rows, so the view keeps a floor height to centre it in.
    func updateStatusFloor(for status: StatusViewModel) {
        if status.showsLoader || status.message != nil {
            statusFloorConstraint?.activate()
        } else {
            statusFloorConstraint?.deactivate()
        }
    }
}

private final class RowTapContainer: UIControl {
    var onTap: (() -> Void)?

    init(contentView: UIView) {
        super.init(frame: .zero)
        contentView.isUserInteractionEnabled = false
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func handleTap() {
        onTap?()
    }
}

private final class SearchContactLoadingView: UIView {
    private enum Constants {
        static let loadingViewSize = CGFloat(64)
    }

    private let loadingView: LoadingView = create {
        $0.contentBackgroundColor = .clear
        $0.contentSize = .init(width: Constants.loadingViewSize, height: Constants.loadingViewSize)
        $0.indicatorImage = UIImage(resource: .searchingUsername)
        $0.tintColor = .fgPrimary
    }

    private let textLabel: Label = create {
        $0.numberOfLines = 0
        $0.textAlignment = .center
        $0.typography = .bodyLargeEmphasized
        $0.textColor = .fgSecondary
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(text: String?) {
        textLabel.text = text
        textLabel.setHidden(text == nil)
    }

    func setLoading(_ loading: Bool) {
        setHidden(!loading)

        if loading {
            loadingView.startAnimating()
        } else {
            loadingView.stopAnimating()
        }
    }

    private func setupLayout() {
        addSubview(loadingView)
        addSubview(textLabel)

        loadingView.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.size.equalTo(Constants.loadingViewSize)
        }

        textLabel.snp.makeConstraints {
            $0.top.equalTo(loadingView.snp.bottom).offset(8)
            $0.leading.trailing.equalToSuperview().inset(24)
        }
    }
}

#Preview("2 contacts found") {
    let layout = SearchContactResultsView()
    let contacts = [
        SearchContactListConfiguration(
            userName: "Jake.23",
            avatarViewModel: .colored(text: "J", colorSeed: "jake")
        ),
        SearchContactListConfiguration(
            userName: "Max.12",
            avatarViewModel: .colored(text: "M", colorSeed: "max")
        )
    ]
    let section = SearchContactResultsView.ViewModel.Section(
        id: "contacts",
        title: nil,
        rows: contacts.identifiedByUUIDs()
    )
    let viewModel = SearchContactResultsView.ViewModel(
        sections: [section],
        status: SearchContactResultsView.StatusViewModel()
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("No search results") {
    let layout = SearchContactResultsView()
    let string = NSAttributedString(string: "No results for\n\"notfoundusername\"")
    let viewModel = SearchContactResultsView.ViewModel(
        sections: [],
        status: SearchContactResultsView.StatusViewModel(message: string)
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("Loading") {
    let layout = SearchContactResultsView()
    let viewModel = SearchContactResultsView.ViewModel(
        sections: [],
        status: SearchContactResultsView.StatusViewModel(
            showsLoader: true,
            loaderText: "Search is taking longer than usual"
        )
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("Multiple sections with headers") {
    let layout = SearchContactResultsView()
    let recentContacts = [
        SearchContactListConfiguration(
            userName: "Alice.01",
            avatarViewModel: .colored(text: "A", colorSeed: "alice")
        ),
        SearchContactListConfiguration(
            userName: "Bob.02",
            avatarViewModel: .colored(text: "B", colorSeed: "bob")
        )
    ]
    let otherContacts = [
        SearchContactListConfiguration(
            userName: "Charlie.03",
            avatarViewModel: .colored(text: "C", colorSeed: "charlie")
        ),
        SearchContactListConfiguration(
            userName: "Diana.04",
            avatarViewModel: .colored(text: "D", colorSeed: "diana")
        )
    ]

    let sections = [
        SearchContactResultsView.ViewModel.Section(
            id: "recent",
            title: "Recent",
            rows: recentContacts.identifiedByUUIDs()
        ),
        SearchContactResultsView.ViewModel.Section(
            id: "other",
            title: "Other",
            rows: otherContacts.identifiedByUUIDs()
        )
    ]
    let viewModel = SearchContactResultsView.ViewModel(
        sections: sections,
        status: SearchContactResultsView.StatusViewModel()
    )
    layout.bind(viewModel: viewModel)
    return layout
}
