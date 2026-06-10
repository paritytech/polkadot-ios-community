import UIKit

final class TransferPrivacyWireframe: TransferPrivacyWireframeProtocol {
    func showInfo(from view: TransferPrivacyViewProtocol?) {
        let learnTitle = String(localized: .Transfer.sheetDegradedLearnMoreTitle)
        let learnDetails = String(localized: .Transfer.sheetDegradedLearnMoreDetails)

        let model = PrivacyLearnMoreModel(title: learnTitle, details: [learnDetails])
        let learnMoreVC = PrivacyLearnMoreViewController(models: [model])
        view?.controller.navigationController?.pushViewController(learnMoreVC, animated: true)
    }

    func complete(from view: TransferPrivacyViewProtocol?, _ completion: (() -> Void)?) {
        view?.controller.dismiss(animated: true, completion: completion)
    }

    func close(from view: TransferPrivacyViewProtocol?) {
        view?.controller.dismiss(animated: true, completion: nil)
    }
}
