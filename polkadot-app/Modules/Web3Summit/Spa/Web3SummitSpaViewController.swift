import UIKit
import SwiftUI
import SnapKit
import PolkadotUI

final class Web3SummitSpaViewController: UIViewController {
    let presenter: Web3SummitSpaPresenterProtocol

    private let spaController: UIViewController
    private let overlayModel = Web3SummitSpaOverlayModel()

    init(
        presenter: Web3SummitSpaPresenterProtocol,
        spaController: UIViewController
    ) {
        self.presenter = presenter
        self.spaController = spaController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .bgSurfaceMain

        embedSpa()
        embedOverlay()

        presenter.setup()
    }
}

private extension Web3SummitSpaViewController {
    func embedSpa() {
        addChild(spaController)
        view.addSubview(spaController.view)
        spaController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        spaController.didMove(toParent: self)
    }

    func embedOverlay() {
        let overlay = Web3SummitSpaOverlay(
            model: overlayModel,
            onStart: { [weak self] in self?.presenter.didTapStart() },
            onSkip: { [weak self] in self?.presenter.didTapSkip() }
        )

        let hosting = UIHostingController(rootView: overlay)
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        view.addSubview(hosting.view)

        hosting.view.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        hosting.didMove(toParent: self)
    }
}

extension Web3SummitSpaViewController: Web3SummitSpaViewProtocol {
    func didReceive(isSkippable: Bool) {
        overlayModel.isSkippable = isSkippable
    }

    func didReceive(attendanceStatus: Web3SummitAttendanceStatus) {
        overlayModel.attendanceStatus = attendanceStatus
    }
}
