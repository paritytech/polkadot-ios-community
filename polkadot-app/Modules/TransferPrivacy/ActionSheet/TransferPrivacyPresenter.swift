import Foundation

final class TransferPrivacyPresenter {
    weak var view: TransferPrivacyViewProtocol?

    private let model: TransferPrivacyModel
    private let wireframe: TransferPrivacyWireframeProtocol
    private let onMainTapped: (() -> Void)?
    private let onSecondaryTapped: () -> Void

    init(
        model: TransferPrivacyModel,
        wireframe: TransferPrivacyWireframeProtocol,
        onMainTapped: (() -> Void)?,
        onSecondaryTapped: @escaping () -> Void
    ) {
        self.model = model
        self.wireframe = wireframe
        self.onMainTapped = onMainTapped
        self.onSecondaryTapped = onSecondaryTapped
    }
}

extension TransferPrivacyPresenter: TransferPrivacyPresenterProtocol {
    func setup() {
        let messageText = model.nonDegradedAmount.map { nonDegradedTitle in
            String(
                localized: .Transfer.sheetDegradedMessageWithDegraded(
                    nonDegraded: nonDegradedTitle,
                    full: model.fullAmount,
                    degraded: model.degradedAmount
                )
            )
        } ?? String(localized: .Transfer.sheetDegradedMessageFull(full: model.fullAmount))

        let viewModel = TransferPrivacyViewModel(
            title: String(localized: .Transfer.sheetDegradedTitle),
            message: messageText,
            linkTitle: String(localized: .Transfer.sheetActionLearnMore(degraded: model.degradedAmount)),
            mainActionTitle: model.nonDegradedAmount
                .map { String(localized: .Transfer.sheetActionSendPrivately(nonDegraded: $0)) },
            secondaryActionTitle: String(localized: .Transfer.sheetActionSendFull(full: model.fullAmount))
        )
        view?.didReceive(viewModel: viewModel)
    }

    func activateLink() {
        wireframe.showInfo(from: view)
    }

    func selectMain() {
        wireframe.complete(from: view, onMainTapped)
    }

    func selectSecondary() {
        wireframe.complete(from: view) { [weak self] in self?.onSecondaryTapped() }
    }

    func cancel() {
        wireframe.close(from: view)
    }
}
