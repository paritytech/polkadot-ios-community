import Foundation
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

struct RustChatExecutionBridgeTests {
    /// Only the dependency factory needs the main actor; the suite must not, because
    /// `awaitBlocking` parks the calling thread on a semaphore.
    private func makeBridge(api: RecordingChatMessaging) async -> RustChatExecutionBridge {
        await RustChatExecutionBridge(
            dependencies: MainActor.run { makeChatBridgeDependencies() },
            chatMessaging: api
        )
    }

    /// Runs a bridge call the way the core does, off the cooperative pool.
    ///
    /// `awaitBlocking` parks its caller on a semaphore and waits for a detached task,
    /// which needs a pool thread to finish. Calling it straight from an async test
    /// parks a pool thread instead, and with the suite running in parallel that
    /// starves the detached tasks on a machine with few cores until they time out.
    private func offPool<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    @Test func createRoomMapsRegistrationStatus() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)

        api.createRoomStatus = .new
        #expect(try await offPool { try bridge.createRoom(roomId: "r", name: "n", icon: "i") } == .new)

        api.createRoomStatus = .exists
        #expect(try await offPool { try bridge.createRoom(roomId: "r", name: "n", icon: "i") } == .exists)
    }

    /// Empty name and icon mean "unset" to the native api, not empty strings.
    @Test func createRoomNormalisesEmptyFields() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)
        _ = try await offPool { try bridge.createRoom(roomId: "r", name: "", icon: "") }
        _ = try await offPool { try bridge.createRoom(roomId: "r2", name: "kept", icon: "icon") }

        #expect(api.createdRooms.first?.name == nil)
        #expect(api.createdRooms.first?.icon == nil)
        #expect(api.createdRooms.last?.name == "kept")
        #expect(api.createdRooms.last?.icon == "icon")
    }

    @Test func postMessageForwardsTextAndCustomOnly() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)

        let messageId = try await offPool { try bridge.postMessage(roomId: "r", content: .text(text: "hi")) }
        #expect(api.sentMessages.count == 1)
        #expect(api.sentRoomIds == ["r"])
        #expect(messageId == "msg-1")

        _ = try await offPool {
            try bridge.postMessage(
                roomId: "r",
                content: .custom(ChatCustomMessage(messageType: "t", payload: Data([1])))
            )
        }
        #expect(api.sentMessages.count == 2)
        if case let .custom(messageType, data) = api.sentMessages.last {
            #expect(messageType == "t")
            #expect(data == Data([1]))
        } else {
            Issue.record("a custom message must keep its type and payload")
        }

        await #expect(throws: HostRejection.self) {
            try await offPool {
                try bridge.postMessage(
                    roomId: "r",
                    content: .reaction(ChatReaction(messageId: "m", emoji: "x"))
                )
            }
        }
        #expect(api.sentMessages.count == 2)
    }

    /// A failing surface must surface as a rejection, not a silent success.
    @Test func postMessageRejectsWhenTheSurfaceFails() async throws {
        let api = RecordingChatMessaging()
        api.sendMessageError = ProductNativeApiError.messagesNotSupported
        let bridge = await makeBridge(api: api)

        // Naming the api's own error is what separates this from a 2 s timeout.
        await #expect(throws: ProductNativeApiError.self) {
            try await offPool { try bridge.postMessage(roomId: "r", content: .text(text: "hi")) }
        }
    }

    @Test func registerBotIsRejected() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)

        await #expect(throws: HostRejection.self) {
            try await offPool { try bridge.registerBot(botId: "b", name: "n", icon: "i") }
        }
    }

    @Test func listRoomsReadsTheCurrentRooms() async throws {
        let api = RecordingChatMessaging()
        api.roomsToReturn = [RoomInfo(roomId: "stored", name: nil, icon: nil, participation: .roomHost)]
        let bridge = await makeBridge(api: api)

        let rooms = try await offPool { try bridge.listRooms() }

        #expect(rooms.map(\.roomId) == ["stored"])
        #expect(rooms.map(\.participatingAs) == [.roomHost])
        #expect(api.subscribeRoomsCallCount == 1)
    }

    @Test func listRoomsReportsNoRoomsWhenTheApiHasNone() async throws {
        let api = RecordingChatMessaging()
        api.roomsToReturn = []
        let bridge = await makeBridge(api: api)

        #expect(try await offPool { try bridge.listRooms() }.isEmpty)
    }
}
