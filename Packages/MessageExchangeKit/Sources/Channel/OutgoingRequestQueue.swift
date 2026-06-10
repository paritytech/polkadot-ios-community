import Foundation
import StatementStore
import SDKLogger

final class OutgoingRequestQueue<M: MessageExchange.CodableMessage> {
    typealias Message = M

    private let statementDataCoder: StatementDataCoding
    private let sizeValidator: OutgoingRequestSizeValidating
    private let logger: SDKLoggerProtocol?

    private var queue = [Message]()

    var currentRequest: OutgoingRequest<Message>?

    init(
        statementDataCoder: StatementDataCoding,
        sizeValidator: OutgoingRequestSizeValidating,
        logger: SDKLoggerProtocol?
    ) {
        self.statementDataCoder = statementDataCoder
        self.sizeValidator = sizeValidator
        self.logger = logger
    }
}

extension OutgoingRequestQueue: OutgoingRequestQueueing {
    func attemptRequestExtensionFromQueue() -> Bool {
        guard !queue.isEmpty else {
            return false
        }

        let messagesToRetry = queue
        queue = []

        var hasExtendedRequest = false

        for message in messagesToRetry {
            let result = performMessageAdd(message, isChannelActive: true)

            if
                case let .success(successOutcome) = result,
                successOutcome == .appendedToCurrentRequest {
                hasExtendedRequest = true
            }
        }

        return hasExtendedRequest
    }

    func addMessage(
        _ message: Message,
        isChannelActive: Bool
    ) -> Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    > {
        performMessageAdd(message, isChannelActive: isChannelActive)
    }

    func dequeueMessagesForNewRequest() -> OutgoingRequest<M>? {
        guard !queue.isEmpty else {
            return nil
        }

        let requestId = UUID().uuidString
        var messages = [M]()
        var scaleEncodedData = Data()
        var index = 0

        while true {
            do {
                let newMessages = messages + [queue[index]]

                let newData = try statementDataCoder.encodeToScaleEncodedPayload(.request(.init(
                    requestId: requestId,
                    messages: newMessages
                )))

                if sizeValidator.scaleEncodedPayloadFits(newData) {
                    messages = newMessages
                    scaleEncodedData = newData
                    index += 1
                } else {
                    break
                }

                if index >= queue.count {
                    break
                }
            } catch {
                assertionFailure("Unexpected error: \(error)")
                logger?.error("Unexpected error: \(error)")
                break
            }
        }

        guard !messages.isEmpty, !scaleEncodedData.isEmpty else {
            logger?.error("Data is empty")
            return nil
        }

        queue.removeFirst(index)

        logger?.debug("Added \(messages.count) for size \(scaleEncodedData.count)")

        return .init(
            requestId: requestId,
            messages: messages,
            scaleEncodedPayload: scaleEncodedData
        )
    }
}

private extension OutgoingRequestQueue {
    func makeError(error: Error) -> MessageExchange.AddToQueueError {
        guard let encodingError = error as? StatementDataEncodingError else {
            assertionFailure("Unexpected error: \(error)")
            logger?.error("Unexpected error: \(error)")
            return .encodingFailed
        }
        switch encodingError {
        case .encodingFailed:
            return .encodingFailed
        case .encryptionFailed:
            return .encryptionFailed
        }
    }

    func performMessageAdd(
        _ message: Message,
        isChannelActive: Bool
    ) -> Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    > {
        do {
            // TODO: We use the randow request id and a single value array to check the size
            // Should be redone properly
            let scaleEncodedPayload = try statementDataCoder.encodeToScaleEncodedPayload(
                .request(.init(
                    requestId: UUID().uuidString,
                    messages: [message]
                ))
            )

            if sizeValidator.scaleEncodedPayloadFits(scaleEncodedPayload) {
                return .success(continueAddingToQueue(
                    for: message,
                    isChannelActive: isChannelActive
                ))
            } else {
                return .failure(
                    .messageTooBig(
                        maxSize: sizeValidator.maxPayloadSize,
                        actualSize: scaleEncodedPayload.count
                    )
                )
            }
        } catch {
            let error = makeError(error: error)
            return .failure(error)
        }
    }

    func continueAddingToQueue(
        for message: Message,
        isChannelActive: Bool
    ) -> MessageExchange.AddToQueueResult {
        guard isChannelActive, queue.isEmpty, let currentRequest else {
            return queueMessage(message)
        }

        if currentRequest.messages.contains(message) {
            return .ignored
        }

        let newMessages = currentRequest.messages + [message]

        do {
            let newRequestId = UUID().uuidString

            let scaleEncodedData = try statementDataCoder.encodeToScaleEncodedPayload(
                .request(.init(
                    requestId: newRequestId,
                    messages: newMessages
                ))
            )

            if sizeValidator.scaleEncodedPayloadFits(scaleEncodedData) {
                self.currentRequest = .init(
                    requestId: newRequestId,
                    messages: newMessages,
                    scaleEncodedPayload: scaleEncodedData
                )
                return .appendedToCurrentRequest
            } else {
                return queueMessage(message)
            }
        } catch {
            logger?.error("Encoding error: \(error)")
            return queueMessage(message)
        }
    }

    func queueMessage(_ message: Message) -> MessageExchange.AddToQueueResult {
        if queue.contains(message) {
            return .ignored
        } else {
            queue.append(message)
            return .queued
        }
    }
}
