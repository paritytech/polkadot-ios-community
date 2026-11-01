import Foundation

final class DeviceTransferSenderInteractor {
    weak var presenter: DeviceTransferSenderInteractorOutputProtocol?
}

extension DeviceTransferSenderInteractor: DeviceTransferSenderInteractorInputProtocol {}
