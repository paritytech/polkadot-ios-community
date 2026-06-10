import Foundation

struct BalanceSyncState: EventProtocol {
    func accept(visitor: EventVisitorProtocol) {
        visitor.processBalanceSyncState(event: self)
    }
}
