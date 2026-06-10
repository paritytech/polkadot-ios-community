import Foundation

struct SelectedUsernameChanged: EventProtocol {
    let username: Username?

    func accept(visitor: EventVisitorProtocol) {
        visitor.processSelectedUsernameChanged(event: self)
    }
}
