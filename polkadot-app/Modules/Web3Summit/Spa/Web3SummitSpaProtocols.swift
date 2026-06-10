import UIKitExt

enum Web3SummitAttendanceStatus {
    case notCheckedIn
    case checkedIn
    case confirmed
}

@MainActor
protocol Web3SummitSpaViewProtocol: ControllerBackedProtocol {
    func didReceive(isSkippable: Bool)
    func didReceive(attendanceStatus: Web3SummitAttendanceStatus)
}

@MainActor
protocol Web3SummitSpaPresenterProtocol: AnyObject {
    func setup()
    func didTapStart()
    func didTapSkip()
}

@MainActor
protocol Web3SummitSpaWireframeProtocol: AnyObject {
    func proceed()
}

protocol Web3SummitSpaInteractorProtocol: AnyObject {
    func attendanceStatusUpdates() -> AsyncThrowingStream<Web3SummitAttendanceStatus, Error>
    func markVerifiedManually()
}
