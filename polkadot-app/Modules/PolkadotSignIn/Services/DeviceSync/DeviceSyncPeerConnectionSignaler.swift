import Foundation
import SubstrateSdk
import AsyncExtensions

/// WebRTC signaling over the device sync message transport (statement store).
///
/// Matches Android's `SyncPeerChannelSignaling`: sends/receives
/// `SyncSignalingEnvelope { offerId, message }` through the encrypted device
/// sync transport. SDP is encoded using MinimalSetup SCALE format (via
/// `SdpCoder`). ICE candidates are encoded using MinimalCandidate SCALE format.
actor DeviceSyncPeerConnectionSignaler {
    private let transport: DeviceSyncMessageTransporting
    private let role: CallRole
    private let logger: LoggerProtocol
    private let sdpCoder: SdpCoding = SdpCoder()

    private nonisolated let subject = AsyncReplaySubject<PeerConnectionSignal>(bufferSize: 100)
    private nonisolated let reconnectSubject = AsyncReplaySubject<String>(bufferSize: 1)
    private nonisolated let acceptedOfferIdSubject = AsyncReplaySubject<String>(bufferSize: 1)

    private var listeningTask: Task<Void, Never>?
    private var activeOfferId: String?

    nonisolated var reconnects: AnyAsyncSequence<String> {
        reconnectSubject.eraseToAnyAsyncSequence()
    }

    nonisolated var acceptedOfferIds: AnyAsyncSequence<String> {
        acceptedOfferIdSubject.eraseToAnyAsyncSequence()
    }

    init(
        transport: DeviceSyncMessageTransporting,
        role: CallRole,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.transport = transport
        self.role = role
        self.logger = logger
    }

    deinit {
        logger.debug("Deinit")
    }

    func startListening() {
        guard listeningTask == nil else { return }

        let transport = transport

        listeningTask = Task { [weak self] in
            do {
                for try await batch in transport.messageBatches {
                    guard !Task.isCancelled else { return }
                    await self?.handleMessageBatch(batch)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await self?.handleListeningError(error)
            }
        }
    }

    private func handleListeningError(_ error: Error) {
        logger.error("Message stream failed: \(error)")
    }

    func stopListening() {
        listeningTask?.cancel()
        listeningTask = nil
    }
}

// MARK: - PeerConnectionSignaling

extension DeviceSyncPeerConnectionSignaler: PeerConnectionSignaling {
    nonisolated var signals: AnyAsyncSequence<PeerConnectionSignal> {
        subject.eraseToAnyAsyncSequence()
    }

    func send(_ signal: PeerConnectionSignal) async throws -> (any PeerConnectionSignalStateObserving)? {
        do {
            try await sendSignal(signal)
        } catch {
            logger.error("Sync signaling send failed: \(error)")
        }
        // implement observer if needed
        return nil
    }
}

// MARK: - Incoming

private extension DeviceSyncPeerConnectionSignaler {
    func handleMessageBatch(_ batch: [Data]) {
        let envelopes = batch.compactMap(decodeEnvelope)
        guard !envelopes.isEmpty else { return }

        var latestOfferIndex: Int?
        for (index, envelope) in envelopes.enumerated() where envelope.message.isOffer {
            latestOfferIndex = index
        }

        for (index, envelope) in envelopes.enumerated() {
            if envelope.message.isOffer, index != latestOfferIndex {
                logger.debug("Dropping stale offer in sync signaling batch")
                continue
            }

            let shouldContinue = handleIncoming(envelope)
            if !shouldContinue { break }
        }
    }

    func decodeEnvelope(_ data: Data) -> Chat.DeviceSyncSignalingEnvelope? {
        logger.debug("Raw message (\(data.count) bytes)")

        do {
            let decoder = try ScaleDecoder(data: data)
            return try Chat.DeviceSyncSignalingEnvelope(scaleDecoder: decoder)
        } catch {
            logger.debug("Ignoring undecodable envelope: \(error)")
            return nil
        }
    }

    @discardableResult
    func handleIncoming(_ envelope: Chat.DeviceSyncSignalingEnvelope) -> Bool {
        do {
            switch envelope.message {
            case .reconnected:
                return handleReconnect(offerId: envelope.offerId)

            case let .offer(sdpData):
                return try handleOffer(sdpData, offerId: envelope.offerId)

            case let .answer(sdpData):
                try handleAnswer(sdpData, offerId: envelope.offerId)

            case let .candidates(candidatesData):
                try handleCandidates(candidatesData, offerId: envelope.offerId)
            }
        } catch {
            logger.error("Receive failed: \(error)")
        }

        return true
    }

    func handleReconnect(offerId: String) -> Bool {
        guard offerId == activeOfferId else {
            logger.debug("Ignoring Reconnected with mismatched offerId=\(offerId)")
            return true
        }

        logger.debug("Reconnected signal matched active offerId=\(offerId)")
        reconnectSubject.send(offerId)
        return false
    }

    func handleOffer(_ sdpData: Data, offerId: String) throws -> Bool {
        guard role == .acceptor else {
            logger.debug("Ignoring offer received by initiator")
            return true
        }

        if let activeOfferId {
            if activeOfferId == offerId {
                logger.debug("Dropping duplicate offer for active offerId=\(offerId)")
                return true
            } else {
                logger.debug("New offerId=\(offerId) while active=\(activeOfferId); requesting reconnect")
                reconnectSubject.send(activeOfferId)
                return false
            }
        }

        activeOfferId = offerId
        acceptedOfferIdSubject.send(offerId)

        logger.debug("Offer (\(sdpData.count) bytes), offerId=\(offerId)")
        let decodedSetup = try sdpCoder.decodeSetup(sdpData)
        subject.send(.offer(decodedSetup.setupSdp))

        if !decodedSetup.candidates.isEmpty {
            logger.debug("Offer included \(decodedSetup.candidates.count) candidate(s)")
            subject.send(.candidates(decodedSetup.candidates))
        }

        return true
    }

    func handleAnswer(_ sdpData: Data, offerId: String) throws {
        guard offerId == activeOfferId else {
            logger.debug("Ignoring answer with mismatched offerId=\(offerId)")
            return
        }

        logger.debug("Received answer (\(sdpData.count) bytes), offerId=\(offerId)")
        let decodedSetup = try sdpCoder.decodeSetup(sdpData)
        subject.send(.answer(decodedSetup.setupSdp))
        acceptedOfferIdSubject.send(offerId)

        if !decodedSetup.candidates.isEmpty {
            logger.debug("Answer included \(decodedSetup.candidates.count) candidate(s)")
            subject.send(.candidates(decodedSetup.candidates))
        }
    }

    func handleCandidates(_ data: Data, offerId: String) throws {
        guard offerId == activeOfferId else {
            logger.debug("Ignoring candidates with mismatched offerId=\(offerId)")
            return
        }

        let candidates = try sdpCoder.decodeCandidates(data)
        logger.debug("Received \(candidates.count) candidate(s), offerId=\(offerId)")
        subject.send(.candidates(candidates))
    }
}

// MARK: - Outgoing

private extension DeviceSyncPeerConnectionSignaler {
    func sendSignal(_ signal: PeerConnectionSignal) async throws {
        guard let envelope = try signalingEnvelope(from: signal) else { return }

        let encoder = ScaleEncoder()
        try envelope.encode(scaleEncoder: encoder)

        await transport.send(encoder.encode())
    }

    func signalingEnvelope(
        from signal: PeerConnectionSignal
    ) throws -> Chat.DeviceSyncSignalingEnvelope? {
        switch signal {
        case let .offer(sdp):
            let offerId = UUID().uuidString
            activeOfferId = offerId
            let setup = SdpCoderSetup(setupSdp: sdp, candidates: [])
            logger.debug("Sending offer: \(sdp.count) chars, offerId=\(offerId)")
            return try .init(offerId: offerId, message: .offer(sdpCoder.encodeSetup(setup)))

        case let .answer(sdp):
            guard let offerId = activeOfferId else {
                logger.error("Cannot send answer without active offerId")
                return nil
            }
            let setup = SdpCoderSetup(setupSdp: sdp, candidates: [])
            logger.debug("Sending answer: \(sdp.count) chars, offerId=\(offerId)")
            return try .init(offerId: offerId, message: .answer(sdpCoder.encodeSetup(setup)))

        case let .candidates(candidates):
            guard let offerId = activeOfferId else {
                logger.error("Cannot send candidates without active offerId")
                return nil
            }
            logger.debug("Sending candidates: \(candidates.count) candidates, offerId=\(offerId)")
            return try .init(offerId: offerId, message: .candidates(sdpCoder.encodeCandidates(candidates)))

        case .closed:
            logger.debug("Sync close signal - no-op over device session")
            return nil
        }
    }
}

extension DeviceSyncPeerConnectionSignaler {
    func sendReconnected(offerId: String) async {
        do {
            let envelope = Chat.DeviceSyncSignalingEnvelope(
                offerId: offerId,
                message: .reconnected
            )
            let encoder = ScaleEncoder()
            try envelope.encode(scaleEncoder: encoder)
            await transport.send(encoder.encode())
            logger.debug("Sent Reconnected signal for offerId=\(offerId)")
        } catch {
            logger.error("Failed to send Reconnected: \(error)")
        }
    }
}
