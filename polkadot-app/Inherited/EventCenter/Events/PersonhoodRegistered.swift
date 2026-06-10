import Foundation
import Individuality

struct PersonhoodRegistered: EventProtocol {
    let source: Source
    let personalId: PeoplePallet.PersonalId

    func accept(visitor: EventVisitorProtocol) {
        visitor.processPersonhoodRegistered(event: self)
    }
}

extension PersonhoodRegistered {
    enum Source {
        case game
        case proofOfInk
    }
}

extension PersonhoodRegistered.Source {
    init(_ type: PersonRegistration.IntendedType) {
        switch type {
        case .proofOfInk:
            self = .proofOfInk
        case .game:
            self = .game
        }
    }

    init(_ source: People.RegisteredSource) {
        switch source {
        case .proofOfInk:
            self = .proofOfInk
        case .game:
            self = .game
        }
    }
}
