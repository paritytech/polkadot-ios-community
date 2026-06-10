import Foundation

struct BackupStatusChanged: EventProtocol {
    func accept(visitor: EventVisitorProtocol) {
        visitor.processBackupStatusChanged(event: self)
    }
}
