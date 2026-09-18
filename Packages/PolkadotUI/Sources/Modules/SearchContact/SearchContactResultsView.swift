import DesignSystem
import UIKit
internal import SnapKit
internal import UIKit_iOS

public final class SearchContactResultsView: DiffableCollectionViewProviderView<String, String> {
    private let separatorSuffix = "_separator"
    private let headerSuffix = "_header"

    private let noResultsLabel: Label = create {
        $0.numberOfLines = 0
        $0.textAlignment = .center
    }

    private let loadingView = SearchContactLoadingView()

    private let separatorConfiguration = SeparatorContentConfiguration(
        color: UIColor.strokePrimary,
        height: Constants.separatorHeight,
        insets: NSDirectionalEdgeInsets(top: 0, leading: 64, bottom: 0, trailing: 16)
    )

    public var selectionHandler: ((ItemIdentifierType) -> Void)?
    public var onContentHeightChanged: (() -> Void)?

    private var contentSizeObservation: NSKeyValueObservation?
    private var isStatusVisible = false
    private var lastReportedHeight: CGFloat = 0

    private var modelHeight: CGFloat = 0
    private lazy var rowHeight = measuredHeight(
        of: SearchContactListView(
            configuration: SearchContactListConfiguration(
                userName: "M",
                avatarViewModel: .colored(text: "M", colorSeed: "M")
            )
        )
    )
    private lazy var headerHeight = measuredHeight(
        of: SearchContactSectionHeaderView(
            configuration: SearchContactSectionHeaderConfiguration(title: "M")
        )
    )

    override public func setupViews() {
        backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .none
        collectionView.delegate = self
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        noResultsLabel.setHidden(true)
        loadingView.setHidden(true)

        addSubview(collectionView)
        addSubview(noResultsLabel)
        addSubview(loadingView)

        let centeringLayoutGuide = UILayoutGuide()
        addLayoutGuide(centeringLayoutGuide)

        centeringLayoutGuide.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalToSuperview()
            $0.bottom.equalToSuperview().inset(Constants.bottomSpacing)
        }

        noResultsLabel.snp.makeConstraints {
            $0.centerX.equalTo(centeringLayoutGuide.snp.centerX)
            $0.centerY.equalTo(centeringLayoutGuide.snp.centerY)
            $0.width.lessThanOrEqualTo(centeringLayoutGuide.snp.width)
            $0.height.lessThanOrEqualTo(centeringLayoutGuide.snp.height)
        }

        loadingView.snp.makeConstraints {
            $0.edges.equalTo(centeringLayoutGuide)
        }

        collectionView.snp.makeConstraints {
            $0.top.equalToSuperview()
            $0.leading.trailing.equalToSuperview()
            $0.bottom.equalToSuperview().inset(Constants.bottomSpacing)
        }

        contentSizeObservation = collectionView.observe(
            \.contentSize,
            options: [.new]
        ) { [weak self] _, _ in
            self?.contentHeightDidChange()
        }
    }

    override public func registerCells() {
        super.registerCells()

        CollectionRegistration.registerCell(
            UICollectionViewCell.self,
            for: collectionView,
            reuseId: SearchContactListView.reuseIdentifier
        )

        CollectionRegistration.registerCell(
            UICollectionViewCell.self,
            for: collectionView,
            reuseId: SeparatorContentView.reuseIdentifier
        )

        CollectionRegistration.registerCell(
            UICollectionViewCell.self,
            for: collectionView,
            reuseId: SearchContactSectionHeaderView.reuseIdentifier
        )
    }

    /// Sized from the view model first, because a collection view with an empty frame never
    /// lays out; the content size then only corrects.
    override public var intrinsicContentSize: CGSize {
        let content = max(
            collectionView.contentSize.height,
            modelHeight,
            isStatusVisible ? Constants.statusHeight : 0
        )
        let height = content > 0 ? content + Constants.bottomSpacing : 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
}

public extension SearchContactResultsView {
    struct StatusViewModel {
        public let searchFailReason: NSAttributedString?
        public let showsLoader: Bool
        public let loaderText: String?

        public init(
            searchFailReason: NSAttributedString? = nil,
            showsLoader: Bool = false,
            loaderText: String? = nil
        ) {
            self.searchFailReason = searchFailReason
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

    func bind(status: StatusViewModel) {
        updateStatusVisibility(status)
        noResultsLabel.attributedText = status.searchFailReason
        noResultsLabel.setHidden(status.searchFailReason == nil)
        loadingView.bind(text: status.loaderText)
        loadingView.setLoading(status.showsLoader)
        contentHeightDidChange()
    }

    func bind(viewModel: ViewModel) {
        // The status flag must be current before the snapshot changes `contentSize`, or the KVO
        // resize measures a stale state and the panel dips before the status floor applies.
        modelHeight = expectedHeight(for: viewModel)
        updateStatusVisibility(viewModel.status)
        applySnapshot(sections: viewModel.sections.map { createSectionProvider(for: $0) })
        bind(status: viewModel.status)
    }
}

private extension SearchContactResultsView {
    enum Constants {
        static let statusHeight: CGFloat = 120
        static let sectionTopInset: CGFloat = 16
        static let interItemSpacing: CGFloat = 8
        static let separatorHeight: CGFloat = 1
        static let bottomSpacing: CGFloat = DSSpacings.small
    }

    func contentHeightDidChange() {
        let height = intrinsicContentSize.height
        guard height != lastReportedHeight else {
            return
        }
        lastReportedHeight = height
        invalidateIntrinsicContentSize()
        onContentHeightChanged?()
    }

    func updateStatusVisibility(_ status: StatusViewModel) {
        isStatusVisible = status.showsLoader || status.searchFailReason != nil
    }

    func measuredHeight(of view: UIView) -> CGFloat {
        view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
    }

    /// Mirrors `createSectionProvider`: top inset, then header, rows and separators
    /// with spacing between.
    func expectedHeight(for viewModel: ViewModel) -> CGFloat {
        viewModel.sections.reduce(0) { total, section in
            let headerCount: CGFloat = section.title == nil ? 0 : 1
            let rowCount = CGFloat(section.rows.count)
            let separatorCount = max(rowCount - 1, 0)
            let itemCount = headerCount + rowCount + separatorCount
            let itemsHeight = headerCount * headerHeight
                + rowCount * rowHeight
                + separatorCount * Constants.separatorHeight
            let spacing = Constants.interItemSpacing * max(itemCount - 1, 0)
            return total + Constants.sectionTopInset + itemsHeight + spacing
        }
    }

    func createSectionProvider(for section: ViewModel.Section) -> SectionProviderType {
        var items: [ItemProviderType] = []

        if let title = section.title {
            items.append(
                ItemProviderType(
                    id: section.id + headerSuffix,
                    configuration: SearchContactSectionHeaderConfiguration(title: title),
                    reuseIdentifier: SearchContactSectionHeaderView.reuseIdentifier
                )
            )
        }

        section.rows.enumerated().forEach { offset, item in
            items.append(
                ItemProviderType(
                    id: item.id,
                    configuration: item.configuration,
                    reuseIdentifier: SearchContactListView.reuseIdentifier
                )
            )

            if offset < section.rows.count - 1 {
                items.append(
                    ItemProviderType(
                        id: item.id + separatorSuffix,
                        configuration: separatorConfiguration,
                        reuseIdentifier: SeparatorContentView.reuseIdentifier
                    )
                )
            }
        }

        return SectionProviderType(
            id: section.id,
            itemProviders: items
        ) { _, _ in
            let group = NSCollectionLayoutGroup.list(
                heightDimension: .estimated(60),
                widthDimension: .fractionalWidth(1.0)
            )

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = Constants.interItemSpacing
            section.contentInsets = .init(
                top: Constants.sectionTopInset,
                leading: 16,
                bottom: 0,
                trailing: 16
            )
            return section
        }
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

extension SearchContactResultsView: UICollectionViewDelegate {
    public func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard collectionView.cellForItem(at: indexPath)?.contentView is SearchContactListView,
              let identifier = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        selectionHandler?(identifier)
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
        status: SearchContactResultsView.StatusViewModel(searchFailReason: string)
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
