import UIKit
import Operation_iOS
import Foundation_iOS

final class DeviceTransferReceiverInteractor {
    weak var presenter: DeviceTransferReceiverInteractorOutputProtocol?

    init() {}
}

extension DeviceTransferReceiverInteractor: DeviceTransferReceiverInteractorInputProtocol {}
