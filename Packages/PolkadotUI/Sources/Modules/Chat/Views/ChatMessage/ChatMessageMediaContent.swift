import SwiftUI
import UIKit
internal import SnapKit

// MARK: - Configuration

public struct ChatMessageMediaViewConfiguration: HashableContentConfiguration {
    let previewProvider: ChatMessageMediaPreviewProviding?
    let previewBackgroundColor: UIColor?
    var corners: CornersConfiguration
    let topLeadingInfoProvider: (any ChatMessageOverlayInfoProviding)?
    let bottomTrailingInfoProvider: (any ChatMessageOverlayInfoProviding)?
    let buttonConfigurationProvider: (any ChatMessageMediaButtonConfigurationProviding)?
    let tapOnMedia: () -> Void

    public init(
        previewProvider: ChatMessageMediaPreviewProviding? = nil,
        previewBackgroundColor: UIColor? = nil,
        corners: CornersConfiguration = .all(0),
        topLeadingInfoProvider: (any ChatMessageOverlayInfoProviding)? = nil,
        bottomTrailingInfoProvider: (any ChatMessageOverlayInfoProviding)? = nil,
        buttonConfigurationProvider: (any ChatMessageMediaButtonConfigurationProviding)? = nil,
        tapOnMedia: @escaping () -> Void = {}
    ) {
        self.previewProvider = previewProvider
        self.previewBackgroundColor = previewBackgroundColor
        self.corners = corners
        self.topLeadingInfoProvider = topLeadingInfoProvider
        self.bottomTrailingInfoProvider = bottomTrailingInfoProvider
        self.buttonConfigurationProvider = buttonConfigurationProvider
        self.tapOnMedia = tapOnMedia
    }

    /// Convenience init with static overlay fields.
    /// Converts `status`, `deliveryDetails`, and `buttonConfiguration` into providers.
    public init(
        previewProvider: ChatMessageMediaPreviewProviding? = nil,
        previewBackgroundColor: UIColor? = nil,
        corners: CornersConfiguration = .all(0),
        status: ChatMessageOverlayInfoViewConfiguration?,
        deliveryDetails: ChatMessageOverlayInfoViewConfiguration? = nil,
        buttonConfiguration: ButtonConfiguration? = nil,
        tapOnMedia: @escaping () -> Void = {}
    ) {
        self.init(
            previewProvider: previewProvider,
            previewBackgroundColor: previewBackgroundColor,
            corners: corners,
            topLeadingInfoProvider: status.map { StaticChatMessageOverlayInfoProvider($0) },
            bottomTrailingInfoProvider: deliveryDetails.map { StaticChatMessageOverlayInfoProvider($0) },
            buttonConfigurationProvider: buttonConfiguration?.asProvider(),
            tapOnMedia: tapOnMedia
        )
    }

    public func makeContentView() -> any UIView & UIContentView {
        ChatMessageMediaView(configuration: self)
    }

    public func updated(for _: UIConfigurationState) -> Self { self }

    public static func == (
        lhs: ChatMessageMediaViewConfiguration,
        rhs: ChatMessageMediaViewConfiguration
    ) -> Bool {
        lhs.previewBackgroundColor == rhs.previewBackgroundColor &&
            lhs.previewProvider?.identifier == rhs.previewProvider?.identifier &&
            lhs.topLeadingInfoProvider === rhs.topLeadingInfoProvider &&
            lhs.bottomTrailingInfoProvider === rhs.bottomTrailingInfoProvider &&
            lhs.buttonConfigurationProvider === rhs.buttonConfigurationProvider
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(previewBackgroundColor)
        hasher.combine(previewProvider?.identifier)
        if let provider = topLeadingInfoProvider { hasher.combine(ObjectIdentifier(provider)) }
        if let provider = bottomTrailingInfoProvider { hasher.combine(ObjectIdentifier(provider)) }
        if let provider = buttonConfigurationProvider { hasher.combine(ObjectIdentifier(provider)) }
    }
}

// MARK: - View

final class ChatMessageMediaView: UIView, UIContentView {
    override var intrinsicContentSize: CGSize {
        UIView.layoutFittingExpandedSize
    }

    private let containerView: UIView = .create { view in
        view.backgroundColor = .bgSurfaceContainer
    }

    private let maskLayer = CAShapeLayer()

    private let imageView: UIImageView = .create { view in
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
    }

    private let topLeadingInfoView = ChatMessageOverlayInfoView()
    private let bottomTrailingInfoView = ChatMessageOverlayInfoView()

    private var buttonHostingView: (UIView & UIContentView)?
    private let buttonContainerView = UIView()

    private var currentButtonConfigurationProvider: (any ChatMessageMediaButtonConfigurationProviding)?

    private var previewState = PreviewState()

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set { apply(newValue) }
    }

    var appliedConfiguration: ChatMessageMediaViewConfiguration

    init(configuration: ChatMessageMediaViewConfiguration) {
        appliedConfiguration = configuration
        super.init(frame: .zero)
        setupViews()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerRadius()
        updatePreviewIfNeeded()
    }
}

// MARK: - Setup

private extension ChatMessageMediaView {
    func setupViews() {
        let showMediaTap = UITapGestureRecognizer(target: self, action: #selector(didTapShowMedia))
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(showMediaTap)

        addSubview(containerView)
        containerView.addSubview(imageView)
        containerView.addSubview(buttonContainerView)
        containerView.addSubview(topLeadingInfoView)
        containerView.addSubview(bottomTrailingInfoView)

        buttonContainerView.setHidden(true)
        topLeadingInfoView.setHidden(true)
        bottomTrailingInfoView.setHidden(true)

        setupConstraints()
    }

    func setupConstraints() {
        containerView.snp.makeConstraints { make in
            make.directionalEdges.equalToSuperview()
        }

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        buttonContainerView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(80)
        }

        topLeadingInfoView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(8)
        }

        bottomTrailingInfoView.snp.makeConstraints { make in
            make.bottom.trailing.equalToSuperview().inset(8)
        }
    }

    func updateCornerRadius() {
        if appliedConfiguration.corners.allEqual {
            containerView.layer.mask = nil

            containerView.layer.cornerRadius = appliedConfiguration.corners.topLeft
            containerView.clipsToBounds = true
        } else {
            containerView.layer.cornerRadius = .zero

            maskLayer.frame = containerView.bounds
            maskLayer.path = UIBezierPath(
                roundedRect: containerView.bounds,
                configuration: appliedConfiguration.corners
            ).cgPath
            containerView.layer.mask = maskLayer
        }
    }
}

// MARK: - Apply configuration

private extension ChatMessageMediaView {
    func apply(_ any: UIContentConfiguration) {
        guard let configuration = any as? ChatMessageMediaViewConfiguration else { return }
        appliedConfiguration = configuration

        imageView.backgroundColor = configuration.previewBackgroundColor

        let providerId = configuration.previewProvider?.identifier
        if previewState.needsUpdate(providerId: providerId) {
            previewState.reset()
            previewState.providerId = providerId
            imageView.image = nil
        }
        updatePreviewIfNeeded()

        topLeadingInfoView.bind(provider: configuration.topLeadingInfoProvider)
        bottomTrailingInfoView.bind(provider: configuration.bottomTrailingInfoProvider)
        applyButtonProvider(configuration.buttonConfigurationProvider)
    }

    func applyButtonProvider(_ provider: (any ChatMessageMediaButtonConfigurationProviding)?) {
        currentButtonConfigurationProvider?.stopUpdate()
        currentButtonConfigurationProvider = provider

        if let provider {
            provider.startUpdate { [weak self] buttonConfiguration in
                self?.updateButton(buttonConfiguration)
            }
        } else {
            updateButton(nil)
        }
    }

    func updateButton(_ buttonConfiguration: ChatMessageMediaViewConfiguration.ButtonConfiguration?) {
        guard let buttonConfiguration else {
            buttonContainerView.setHidden(true)
            return
        }

        let swiftUIButton = ChatMessageMediaButton(
            style: buttonConfiguration.style,
            size: buttonConfiguration.size,
            action: buttonConfiguration.action
        )
        let hostingConfiguration = UIHostingConfiguration {
            swiftUIButton
        }

        if let hostingView = buttonHostingView {
            hostingView.configuration = hostingConfiguration
        } else {
            let hostingView = hostingConfiguration.makeContentView()
            buttonHostingView = hostingView
            hostingView.backgroundColor = .clear

            buttonContainerView.addSubview(hostingView)
            hostingView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }

        buttonContainerView.setHidden(false)
    }

    func updatePreviewIfNeeded() {
        let size = containerView.bounds.size
        guard size != .zero else {
            return
        }

        let needsPreview = !previewState.hasRequested || previewState.needsUpdate(size: size)

        guard needsPreview,
              let provider = appliedConfiguration.previewProvider else {
            return
        }

        previewState.hasRequested = true
        previewState.size = size
        provider.providePreview(for: imageView, size: size)
    }

    @objc func didTapShowMedia() {
        appliedConfiguration.tapOnMedia()
    }
}

// MARK: - PreviewState

private extension ChatMessageMediaView {
    struct PreviewState {
        var providerId: String?
        var size: CGSize?
        var hasRequested: Bool = false

        mutating func reset() {
            providerId = nil
            size = nil
            hasRequested = false
        }

        func needsUpdate(providerId: String?) -> Bool {
            self.providerId != providerId
        }

        func needsUpdate(size: CGSize) -> Bool {
            self.size != size
        }
    }
}

#if DEBUG
    #Preview("UIKit - Failed") {
        ChatMessageMediaViewConfiguration(
            corners: .all(16),
            status: .mediaUploadFailed(),
            deliveryDetails: .mediaUploadFailed(),
            buttonConfiguration: .init(style: .retry)
        ).makeContentView()
    }

    #Preview("UIKit - Play") {
        ChatMessageMediaViewConfiguration(
            corners: .all(16),
            status: nil,
            deliveryDetails: nil,
            buttonConfiguration: .init(style: .play)
        ).makeContentView()
    }

    #Preview("UIKit - Sent") {
        ChatMessageMediaViewConfiguration(
            corners: .all(16),
            status: nil,
            deliveryDetails: nil,
        ).makeContentView()
    }

#endif
