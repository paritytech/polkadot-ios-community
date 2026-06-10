import Foundation
import SubstrateSdk
import AsyncExtensions

enum PeerConnectionSignalState {
    case sent
    case delivered
}

protocol PeerConnectionSignalStateObserving: Sendable {
    func wait(for state: PeerConnectionSignalState) async throws
}

protocol PeerConnectionSignaling {
    var signals: AnyAsyncSequence<PeerConnectionSignal> { get }

    func send(_ signal: PeerConnectionSignal) async throws -> PeerConnectionSignalStateObserving?
}

protocol ChatCallMessageReceiving: AnyObject {
    var peerAccountId: AccountId { get }

    func receive(message: Chat.RemoteMessage) async
}
