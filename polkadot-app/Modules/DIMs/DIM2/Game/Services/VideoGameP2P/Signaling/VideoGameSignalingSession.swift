import Foundation
import SubstrateSdk
import AsyncExtensions
import MessageExchangeKit
import Individuality

enum VideoGameSignalingSessionError: Error {
    case peerPublicKeyNotFound
}

/// Implements `PeerConnectionSignaling` for the video game feature.
///
/// Sends and receives `VideoGameSignalingEnvelope` through the MessageExchangeKit
/// peer session infrastructure. Incoming envelopes are filtered by `gameIndex`
/// and `offerId` before being converted to `PeerConnectionSignal`.
final class VideoGameSignalingSession {
    static let pin = "video_game_room"

    let gameIndex: GamePallet.GameIndex
    let peerAccountId: AccountId
    let sdpCoder: SdpCoding
    let logger: LoggerProtocol

    private let exchangeService: AnyMessageExchangeService<OpaqueVideoGameSignalingEnvelope>
    private let peer: MessageExchange.Peer

    /// Buffers WebRTC signaling signals (offer/answer/candidates) so that signals
    /// emitted before the consumer subscribes are not lost.
    /// Replaced with a fresh subject on each reconnection to discard stale signals.
    private var subject = AsyncReplaySubject<PeerConnectionSignal>(bufferSize: 100)

    /// Buffers reconnection offer IDs from the remote peer.
    private let reconnectedSubject = AsyncReplaySubject<String>(bufferSize: 10)
    private let mutex = NSLock()

    private(set) var activeOfferId: String?

    init(
        gameIndex: GamePallet.GameIndex,
        peerAccountId: AccountId,
        exchangeService: AnyMessageExchangeService<OpaqueVideoGameSignalingEnvelope>,
        peer: MessageExchange.Peer,
        sdpCoder: SdpCoding = SdpCoder(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.gameIndex = gameIndex
        self.peerAccountId = peerAccountId
        self.exchangeService = exchangeService
        self.peer = peer
        self.sdpCoder = sdpCoder
        self.logger = logger
    }

    deinit {
        logger.debug("Deinit")
    }

    // MARK: - Reconnection

    /// Stream of incoming `reconnected` offer IDs from the remote peer.
    var reconnectedSignals: AnyAsyncSequence<String> {
        reconnectedSubject.eraseToAnyAsyncSequence()
    }

    func setActiveOfferId(_ offerId: String?) {
        mutex.withLock { activeOfferId = offerId }
    }

    /// Prepares the session for a fresh connection attempt by clearing the
    /// active offer ID and replacing the signal subject so that stale signals
    /// from a previous connection are not delivered to new subscribers.
    func resetForReconnection() {
        mutex.withLock {
            activeOfferId = nil
            subject = AsyncReplaySubject<PeerConnectionSignal>(bufferSize: 100)
        }
    }

    // MARK: - Sending

    func sendReconnected(_ offerId: String) {
        sendEnvelope(offerId: offerId, message: .reconnected)
    }

    // MARK: - Receiving (called by delegate/coordinator)

    func handleIncomingEnvelopes(_ envelopes: [VideoGameSignalingEnvelope]) {
        // Parse inside the lock and capture the current subject reference so
        // that signals are emitted to the correct (not yet replaced) subject.
        let (currentSubject, pendingSignals, pendingReconnections) = mutex.withLock {
            let parsed = parseEnvelopes(envelopes)
            return (subject, parsed.signals, parsed.reconnections)
        }

        for signal in pendingSignals {
            currentSubject.send(signal)
        }

        for offerId in pendingReconnections {
            reconnectedSubject.send(offerId)
        }
    }
}

// MARK: - PeerConnectionSignaling

extension VideoGameSignalingSession: PeerConnectionSignaling {
    var signals: AnyAsyncSequence<PeerConnectionSignal> {
        mutex.withLock { subject }.eraseToAnyAsyncSequence()
    }

    func send(_ signal: PeerConnectionSignal) async throws -> PeerConnectionSignalStateObserving? {
        // Encode inside the lock, send outside to avoid holding the mutex
        // while calling into exchangeService.
        guard let envelope = mutex.withLock({ encodeSignal(signal) }) else {
            return nil
        }

        sendEnvelope(offerId: envelope.offerId, message: envelope.message)

        // Observer can be implemented if it will be ever needed
        return nil
    }
}

// MARK: - Private

private extension VideoGameSignalingSession {
    /// Must be called with mutex held.
    func encodeSignal(
        _ signal: PeerConnectionSignal
    ) -> (offerId: String, message: VideoGameSignalingMessage)? {
        do {
            switch signal {
            case let .offer(sdp):
                let offerId = UUID().uuidString
                activeOfferId = offerId

                let setup = SdpCoderSetup(setupSdp: sdp, candidates: [])
                let encoded = try sdpCoder.encodeSetup(setup)
                return (offerId, .offer(encoded))

            case let .answer(sdp):
                guard let offerId = activeOfferId else {
                    logger.error("Cannot send answer without active offer ID")
                    return nil
                }

                let setup = SdpCoderSetup(setupSdp: sdp, candidates: [])
                let encoded = try sdpCoder.encodeSetup(setup)
                return (offerId, .answer(encoded))

            case let .candidates(candidates):
                guard let offerId = activeOfferId else {
                    logger.error("Cannot send candidates without active offer ID")
                    return nil
                }

                let encoded = try sdpCoder.encodeCandidates(candidates)
                return (offerId, .iceCandidates(encoded))

            case .closed:
                logger.debug("Video game signaling does not propagate closed signal")
                return nil
            }
        } catch {
            logger.error("Signal encoding failed: \(error)")
            return nil
        }
    }

    func sendEnvelope(offerId: String, message: VideoGameSignalingMessage) {
        let envelope = VideoGameSignalingEnvelope(
            gameIndex: gameIndex,
            offerId: offerId,
            message: message
        )

        exchangeService.addMessageToQueue(OpaqueMessageWrapper(message: envelope), for: peer)
    }

    /// Must be called with mutex held.
    ///
    /// When multiple offers or reconnected events accumulate in a single batch,
    /// only the latest of each is used — earlier ones are stale and get discarded.
    func parseEnvelopes(
        _ envelopes: [VideoGameSignalingEnvelope]
    ) -> (signals: [PeerConnectionSignal], reconnections: [String]) {
        let relevant = envelopes.filter { $0.gameIndex == gameIndex }
        let deduplicated = dropStaleEnvelopes(relevant)

        var signals: [PeerConnectionSignal] = []
        var reconnections: [String] = []

        for envelope in deduplicated {
            parseEnvelope(envelope, signals: &signals, reconnections: &reconnections)
        }

        return (signals, reconnections)
    }

    /// Keeps only the latest offer and the latest reconnected event,
    /// drops earlier duplicates of each.
    func dropStaleEnvelopes(
        _ envelopes: [VideoGameSignalingEnvelope]
    ) -> [VideoGameSignalingEnvelope] {
        var latestOfferIndex: Int?
        var latestReconnectedIndex: Int?

        for (index, envelope) in envelopes.enumerated() {
            if envelope.message.isOffer {
                latestOfferIndex = index
            } else if envelope.message.isReconnected {
                latestReconnectedIndex = index
            }
        }

        return envelopes
            .enumerated()
            .filter { index, envelope in
                if envelope.message.isOffer {
                    return index == latestOfferIndex
                }
                if envelope.message.isReconnected {
                    return index == latestReconnectedIndex
                }
                return true
            }
            .map(\.element)
    }

    /// Must be called with mutex held.
    func parseEnvelope(
        _ envelope: VideoGameSignalingEnvelope,
        signals: inout [PeerConnectionSignal],
        reconnections: inout [String]
    ) {
        switch envelope.message {
        case .reconnected:
            reconnections.append(envelope.offerId)

        case let .offer(sdpData):
            handleOffer(sdpData, offerId: envelope.offerId, signals: &signals)

        case let .answer(sdpData):
            handleAnswer(sdpData, offerId: envelope.offerId, signals: &signals)

        case let .iceCandidates(candidatesData):
            handleCandidates(candidatesData, offerId: envelope.offerId, signals: &signals)
        }
    }

    /// Must be called with mutex held.
    func handleOffer(_ sdpData: Data, offerId: String, signals: inout [PeerConnectionSignal]) {
        do {
            let setup = try sdpCoder.decodeSetup(sdpData)
            activeOfferId = offerId

            signals.append(.offer(setup.setupSdp))

            if !setup.candidates.isEmpty {
                signals.append(.candidates(setup.candidates))
            }

            logger.debug("Received offer with ID: \(offerId)")
        } catch {
            logger.error("Failed to decode offer SDP: \(error)")
        }
    }

    func handleAnswer(_ sdpData: Data, offerId: String, signals: inout [PeerConnectionSignal]) {
        guard offerId == activeOfferId else {
            logger.debug("Ignoring answer with mismatched offer ID: \(offerId)")
            return
        }

        do {
            let setup = try sdpCoder.decodeSetup(sdpData)
            signals.append(.answer(setup.setupSdp))

            if !setup.candidates.isEmpty {
                signals.append(.candidates(setup.candidates))
            }

            logger.debug("Received answer for offer: \(offerId)")
        } catch {
            logger.error("Failed to decode answer SDP: \(error)")
        }
    }

    func handleCandidates(_ data: Data, offerId: String, signals: inout [PeerConnectionSignal]) {
        guard offerId == activeOfferId else {
            logger.debug("Ignoring candidates with mismatched offer ID: \(offerId)")
            return
        }

        do {
            let candidates = try sdpCoder.decodeCandidates(data)
            signals.append(.candidates(candidates))

            logger.debug("Received \(candidates.count) ICE candidates")
        } catch {
            logger.error("Failed to decode ICE candidates: \(error)")
        }
    }
}
