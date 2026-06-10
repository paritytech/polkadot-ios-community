import Foundation

struct FullUsernameClaimed: EventProtocol {
    let liteUsername: Username
    let fullUsername: Username
    let source: PersonhoodRegistered.Source

    func accept(visitor: EventVisitorProtocol) {
        visitor.processFullUsernameClaimed(event: self)
    }
}
