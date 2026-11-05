import Foundation
import AsyncExtensions
import MessageExchangeKit

protocol DeviceTransferPeerComponentMaking: Sendable {
    func makeSignalingSession(delegate: AnyPeerSessionDelegate<Data>) async throws -> DeviceSyncSignalingSession
    func makeConnectionFlow(session: DeviceSyncSignalingSession) -> any DevicePeerConnectionFlowing
}

/// Must subscribe to the flow before starting it, or the first control message is lost.
typealias DeviceTransferConnectionRun = @Sendable (any DevicePeerConnectionFlowing) async throws -> Void

enum DeviceTransferContextError: Error, Equatable {
    case rejected
    case idleTimeout
}

struct DeviceTransferPeerContextSettings {
    var idleTimeout = DeviceTransferConstants.runIdleTimeout
    var restartDelayPolicy = DeviceSyncRestartDelayPolicy()
    var clock: any Clock<Duration> = ContinuousClock()
}

actor DeviceTransferPeerContext {
    fileprivate enum Outcome {
        case completed
        case ended
    }

    private let components: any DeviceTransferPeerComponentMaking
    private let sessionDelegate: any DeviceSyncPeerSessionDelegating
    private let rejections: AsyncStream<Void>
    private let settings: DeviceTransferPeerContextSettings
    private let logger: LoggerProtocol
    private let idleSignals: AsyncStream<Void>
    private let idleContinuation: AsyncStream<Void>.Continuation

    private var onEvent: DeviceTransferRunEventHandler = { _ in }
    private var idleTimer: Task<Void, Never>?
    private var isConnected = false
    private var currentAttempt: Task<Void, Error>?
    private var isReplacingAttempt = false

    init(
        components: any DeviceTransferPeerComponentMaking,
        sessionDelegate: any DeviceSyncPeerSessionDelegating,
        rejections: AsyncStream<Void>,
        settings: DeviceTransferPeerContextSettings = DeviceTransferPeerContextSettings(),
        logger: LoggerProtocol
    ) {
        self.components = components
        self.sessionDelegate = sessionDelegate
        self.rejections = rejections
        self.settings = settings
        self.logger = logger
        (idleSignals, idleContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func run(
        onEvent: @escaping DeviceTransferRunEventHandler = { _ in },
        _ connectionRun: @escaping DeviceTransferConnectionRun
    ) async throws {
        self.onEvent = onEvent
        let session = try await components.makeSignalingSession(delegate: AnyPeerSessionDelegate(sessionDelegate))
        restartIdleTimer()

        defer {
            idleTimer?.cancel()
            currentAttempt?.cancel()
            sessionDelegate.finishIncomingEnvelopes()
        }

        do {
            try await runUntilCompleted(session: session, connectionRun: connectionRun)
            await session.close()
        } catch {
            await session.close()
            throw error
        }
    }
}

private extension DeviceTransferPeerContext {
    func runUntilCompleted(
        session: DeviceSyncSignalingSession,
        connectionRun: @escaping DeviceTransferConnectionRun
    ) async throws {
        try await withThrowingTaskGroup(of: Outcome.self) { group in
            group.addTask { try await self.connectUntilCompleted(session: session, connectionRun: connectionRun) }
            group.addTask { await self.pumpEnvelopes(into: session) }
            group.addTask { try await self.failOnRejection() }
            group.addTask { try await self.failOnIdle() }

            while let outcome = try await group.next() {
                if outcome == .completed {
                    group.cancelAll()
                    return
                }
            }
        }
    }

    func connectUntilCompleted(
        session: DeviceSyncSignalingSession,
        connectionRun: @escaping DeviceTransferConnectionRun
    ) async throws -> Outcome {
        var failedAttempts = 0

        while true {
            try Task.checkCancellation()

            let attempt = await startAttempt(
                session: session,
                isRetry: failedAttempts > 0 || isReplacingAttempt,
                connectionRun: connectionRun
            )

            do {
                try await withTaskCancellationHandler {
                    try await attempt.value
                } onCancel: {
                    attempt.cancel()
                }
                return .completed
            } catch let DeviceTransferRunError.aborted(reason) {
                throw DeviceTransferRunError.aborted(reason)
            } catch {
                try Task.checkCancellation()
                try await waitBeforeRetry(after: error, failedAttempts: &failedAttempts)
            }
        }
    }

    func startAttempt(
        session: DeviceSyncSignalingSession,
        isRetry: Bool,
        connectionRun: @escaping DeviceTransferConnectionRun
    ) async -> Task<Void, Error> {
        if isRetry {
            if let offerId = await session.currentReconnectOfferId() {
                await session.sendReconnected(offerId: offerId)
            }
            await session.resetForReconnection()
        }

        isReplacingAttempt = false
        let flow = components.makeConnectionFlow(session: session)
        let states = await flow.states.makeAsyncIterator()

        let attempt = Task { [weak self] in
            let observer = Task { await self?.observe(states) }
            defer { observer.cancel() }

            do {
                try await connectionRun(flow)
                await flow.cancel()
            } catch {
                await flow.cancel()
                throw error
            }
        }

        currentAttempt = attempt
        return attempt
    }

    func waitBeforeRetry(after error: Error, failedAttempts: inout Int) async throws {
        setConnected(false)

        guard !isReplacingAttempt else { return }

        failedAttempts += 1
        let delay = settings.restartDelayPolicy.delay(forAttempt: failedAttempts)
        logger.warning("Device transfer connection failed: \(error); retrying in \(delay)")
        try await settings.clock.sleep(for: delay)
    }

    func observe(_ initialStates: AnyAsyncIterator<DeviceSyncDataChannelState>) async {
        var states = initialStates
        while let state = try? await states.next() {
            setConnected(state == .connected)
        }
    }

    func pumpEnvelopes(into session: DeviceSyncSignalingSession) async -> Outcome {
        for await batch in sessionDelegate.incomingEnvelopes {
            restartIdleTimer()
            onEvent(.peerFound)

            if let reconnection = await session.reconnection(in: batch) {
                logger.debug("Device transfer reconnect accepted for offer \(reconnection.offerId)")
                replaceCurrentAttempt()
                await session.handleIncomingEnvelopes(reconnection.following)
                continue
            }

            await session.handleIncomingEnvelopes(batch)
        }

        return .ended
    }

    func replaceCurrentAttempt() {
        isReplacingAttempt = true
        currentAttempt?.cancel()
    }

    func failOnRejection() async throws -> Outcome {
        for await _ in rejections {
            throw DeviceTransferContextError.rejected
        }
        return .ended
    }

    func failOnIdle() async throws -> Outcome {
        for await _ in idleSignals {
            throw DeviceTransferContextError.idleTimeout
        }
        return .ended
    }

    func setConnected(_ connected: Bool) {
        guard isConnected != connected else { return }
        isConnected = connected

        if connected {
            idleTimer?.cancel()
            idleTimer = nil
            onEvent(.channelOpened)
        } else {
            restartIdleTimer()
        }
    }

    func restartIdleTimer() {
        idleTimer?.cancel()
        guard !isConnected else { return }

        let timeout = settings.idleTimeout
        let clock = settings.clock
        let continuation = idleContinuation

        idleTimer = Task {
            guard await (try? clock.sleep(for: timeout)) != nil, !Task.isCancelled else { return }
            continuation.yield()
        }
    }
}
