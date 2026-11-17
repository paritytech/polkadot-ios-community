import UIKit
import UIKit_iOS
import Foundation_iOS
import FoundationExt
import AsyncExtensions

final class AccountRecoveryViewController: UIViewController, ViewHolder {
    typealias RootViewType = AccountRecoveryViewLayout

    let presenter: AccountRecoveryPresenterProtocol
    private let appStateStreamFactory: ApplicationStateStreamFactory

    var keyboardHandler: KeyboardHandler?

    private var isSceneCaptured = false
    private var isResignedActive = false
    private var appStateTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init(
        presenter: AccountRecoveryPresenterProtocol,
        appStateStreamFactory: ApplicationStateStreamFactory
    ) {
        self.presenter = presenter
        self.appStateStreamFactory = appStateStreamFactory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        appStateTask?.cancel()
    }

    override func loadView() {
        view = AccountRecoveryViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addHandlers()
        observeInputExposure()

        presenter.setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if keyboardHandler == nil {
            setupKeyboardHandler()
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        isSceneCaptured = traitCollection.sceneCaptureState == .active
        updateInputCover()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        rootView.textView.becomeFirstResponder()
    }
}

// MARK: - AccountRecoveryViewProtocol

extension AccountRecoveryViewController: AccountRecoveryViewProtocol {
    func didReceive(inputViewModel: any InputViewModelProtocol) {
        rootView.bind(inputViewModel: inputViewModel)
    }
}

// MARK: - KeyboardAdoptable

extension AccountRecoveryViewController: KeyboardAdoptable {}

// MARK: - Private

private extension AccountRecoveryViewController {
    func addHandlers() {
        rootView.proceedButton.addTarget(
            self,
            action: #selector(actionProceed),
            for: .touchUpInside
        )
    }

    @objc
    func actionProceed() {
        presenter.proceed()
    }

    func observeInputExposure() {
        registerForTraitChanges([UITraitSceneCaptureState.self]) { (self: Self, _: UITraitCollection) in
            self.isSceneCaptured = self.traitCollection.sceneCaptureState == .active
            self.updateInputCover()
        }

        appStateTask = observeApplicationActivity()
    }

    func observeApplicationActivity() -> Task<Void, Never> {
        let resignEvents = appStateStreamFactory.stream(for: .willResignActive).map { true }
        let activeEvents = appStateStreamFactory.stream(for: .didBecomeActive).map { false }

        return Task { [weak self] in
            for await isResignedActive in merge(resignEvents, activeEvents) {
                self?.isResignedActive = isResignedActive
                self?.updateInputCover()
            }
        }
    }

    func updateInputCover() {
        rootView.setInputCovered(isSceneCaptured || isResignedActive)
    }
}
