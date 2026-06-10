import Foundation

struct ImmediateSignalStateObserver: PeerConnectionSignalStateObserving {
    func wait(for _: PeerConnectionSignalState) async throws {}
}
