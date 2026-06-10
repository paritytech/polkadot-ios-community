import Foundation
import SubstrateSdk
import AsyncAlgorithms
import AsyncExtensions
import WebRTC

enum MultiplexedDataChannelError: Error {
    case sendFailed
}

final class MultiplexedDataChannel {
    private let dataChannelWrapper: AsyncDataChannelWrapper
    private let logger: LoggerProtocol

    private let lock = NSLock()
    private var subscribers: [String: AsyncChannel<Data>] = [:]
    private var demuxTask: Task<Void, Never>?

    init(dataChannelWrapper: AsyncDataChannelWrapper, logger: LoggerProtocol) {
        self.dataChannelWrapper = dataChannelWrapper
        self.logger = logger
    }

    deinit {
        demuxTask?.cancel()

        lock.lock()
        let channels = subscribers.values
        lock.unlock()

        for channel in channels {
            channel.finish()
        }
    }

    func start() {
        demuxTask = Task { [weak self] in
            guard let self else { return }

            for await buffer in dataChannelWrapper.messages {
                guard !Task.isCancelled else { return }

                do {
                    let decoder = try ScaleDecoder(data: buffer.data)
                    let message = try DataChannelMessage(scaleDecoder: decoder)

                    let channel = subscriber(for: message.id)

                    if let channel {
                        await channel.send(message.data)
                    } else {
                        logger.warning("No subscriber for use case: \(message.id)")
                    }
                } catch {
                    logger.error("DataChannelMessage decoding failed: \(error)")
                }
            }
        }
    }

    func subscribe(useCaseId: String) -> AnyAsyncSequence<Data> {
        lock.lock()
        defer { lock.unlock() }

        if let existing = subscribers[useCaseId] {
            return existing.eraseToAnyAsyncSequence()
        }

        let channel = AsyncChannel<Data>()
        subscribers[useCaseId] = channel
        return channel.eraseToAnyAsyncSequence()
    }

    private nonisolated func subscriber(for id: String) -> AsyncChannel<Data>? {
        lock.lock()
        defer { lock.unlock() }
        return subscribers[id]
    }

    func send(data: Data, useCaseId: String) throws {
        do {
            let message = DataChannelMessage(id: useCaseId, data: data)
            let encoded = try message.scaleEncoded()
            let didSend = dataChannelWrapper.dataChannel.sendData(
                RTCDataBuffer(data: encoded, isBinary: true)
            )

            guard didSend else {
                throw MultiplexedDataChannelError.sendFailed
            }
        } catch {
            logger.error("DataChannelMessage encoding failed: \(error)")
            throw error
        }
    }
}
