import Foundation
import WebRTC
import AsyncExtensions
import AsyncAlgorithms

final class AsyncDataChannelWrapper: NSObject {
    let dataChannel: RTCDataChannel

    private let dataChannelDelegateQueue = DispatchQueue(label: "io.async.data.channel.wrapper.queue")

    let state: AsyncCurrentValueSubject<RTCDataChannelState>
    let logger: LoggerProtocol
    let messages: AsyncChannel<RTCDataBuffer> = .init()

    private var producerTask: Task<Void, Never>?
    private var messagesStream: AsyncStream<RTCDataBuffer>?
    private var messagesContinuation: AsyncStream<RTCDataBuffer>.Continuation?

    init(dataChannel: RTCDataChannel, logger: LoggerProtocol) {
        self.dataChannel = dataChannel
        state = .init(dataChannel.readyState)
        self.logger = logger
    }

    deinit {
        Logger.shared.debug("Deinited")
        messagesContinuation?.finish()
        producerTask?.cancel()
    }

    func setup() {
        setupDataBufferStreaming()

        dataChannel.delegate = self
    }
}

private extension AsyncDataChannelWrapper {
    func setupDataBufferStreaming() {
        messagesStream = AsyncStream { [weak self] continuation in
            self?.messagesContinuation = continuation
        }

        producerTask = Task { [messages, messagesStream] in
            guard let messagesStream else {
                return
            }

            for await buffer in messagesStream {
                await messages.send(buffer)
            }

            messages.finish()
        }
    }
}

extension AsyncDataChannelWrapper: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        logger.debug("State: \(dataChannel.readyState)")

        dataChannelDelegateQueue.async {
            self.state.send(dataChannel.readyState)
        }
    }

    func dataChannel(_: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        logger.debug("Data channel: \(buffer.data.count)")

        dataChannelDelegateQueue.async { [weak self] in
            // we can't directly use channel here as it requires async context
            // the idea is to first put the buffer into the stream and then to the channel
            // to ensure correct order avoding race condition
            if let messagesContinuation = self?.messagesContinuation {
                self?.logger.debug("Data saving: \(buffer.data.count)")
                messagesContinuation.yield(buffer)
            } else {
                self?.logger.error("Missed buffer: \(buffer.data.count)")
            }
        }
    }
}
