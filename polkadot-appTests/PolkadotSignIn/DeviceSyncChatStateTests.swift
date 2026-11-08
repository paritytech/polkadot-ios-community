@testable import polkadot_app
import CoreData
import Foundation
import MessageExchangeKit
import Operation_iOS
import SubstrateSdk
import Testing

/// The old phone's store (`sender`) is collected and applied to the new phone's store (`receiver`), both real
/// in-memory stores.
@Suite(.timeLimit(.minutes(1)))
struct DeviceSyncChatStateTests {
    private let sender = UserDataStorageTestFacade()
    private let receiver = UserDataStorageTestFacade()
    private let peer = Data(repeating: 7, count: 32)
    private let remoteContact: Chat.RemoteContact

    init() throws {
        remoteContact = try Chat.RemoteContact(
            accountId: Data(repeating: 7, count: 32),
            username: "peer",
            chatPublicKey: Chat.PublicKey(rawData: Data(repeating: 1, count: 32)),
            imageData: nil
        )
    }

    @Test("Decided incoming requests keep their rediscovered statements out; an undecided one isn't transferred")
    func decidedIncomingRequestsAreDeduplicated() async throws {
        try await insertIncomingRequest("accepted", status: .incoming(.accepted))
        try await insertIncomingRequest("declined", status: .incoming(.declined))
        try await insertIncomingRequest("undecided", status: .incoming(.new))

        try await transfer(after: nil)

        let store = makeRequestStoreService()
        #expect(try await store.fetchByRequestId("accepted") != nil)
        #expect(try await store.fetchByRequestId("declined") != nil)
        #expect(try await store.fetchByRequestId("undecided") == nil)
    }

    @Test("A blocked contact stays blocked on the new phone")
    func blockedContactStaysBlocked() async throws {
        try await insertContact(in: sender)
        try await setBlocked(true, in: sender)
        try await insertContact(in: receiver)

        try await transfer(after: nil)

        #expect(try await isBlocked(in: receiver))
    }

    @Test("A pending outgoing request is renewed from the new phone with the same content")
    func pendingOutgoingRequestIsRenewed() async throws {
        let message = Chat.RequestMessage(
            messageId: "outgoing",
            timestamp: 1_000,
            content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
        )
        try await insertOutgoingRequest(message, in: sender)

        try await transfer(after: nil)

        let candidates = try await ChatRequestOutgoingStore(storageFacade: receiver).renewalCandidates()
        #expect(candidates.map(\.input.message) == [message])
    }

    @Test("Changes after the checkpoint travel incrementally: an unblock and a decided request")
    func incrementalChangesAfterCheckpoint() async throws {
        try await insertContact(in: sender)
        try await setBlocked(true, in: sender)
        try await insertContact(in: receiver)
        try await transfer(after: nil)
        let checkpoint = Date()

        try await setBlocked(false, in: sender)
        try await insertIncomingRequest("accepted-later", status: .incoming(.accepted))
        try await transfer(after: checkpoint)

        #expect(try await isBlocked(in: receiver) == false)
        #expect(try await makeRequestStoreService().fetchByRequestId("accepted-later") != nil)
    }

    @Test("A status update for a request the new phone doesn't have leaves discovery's lookup working")
    func statusUpdateForUnknownRequestIsIgnored() async throws {
        try await makeApplier().applyIncomingStatusUpdates([
            Chat.DeviceSyncIncomingRequestStatusUpdate(requestId: "unknown", status: .accepted)
        ])

        #expect(try await makeRequestStoreService().fetchByRequestId("unknown") == nil)
    }

    @Test("Applying synced changes doesn't mark them modified, so they aren't sent back")
    func appliedChangesAreNotEchoed() async throws {
        try await insertContact(in: sender)
        try await setBlocked(true, in: sender)
        try await insertContact(in: receiver)
        try await insertIncomingRequest("accepted", status: .incoming(.accepted))
        let checkpoint = Date()

        try await transfer(after: nil)

        let echoed = try await DeviceSyncChatStateCollector(databaseService: receiver.databaseService)
            .collect(after: checkpoint)
        #expect(echoed.isEmpty)
    }

    @Test("Contact devices arrive with their status and peer time; only active ones route, nothing is sent back")
    func contactDevicesTravelWithStatus() async throws {
        let kept = makeDevice(0x21)
        let removed = makeDevice(0x22)
        try await insertContact(in: sender)
        try await insertContact(in: receiver)
        try await updateDevices(
            [
                .added(kept, changedAt: 10),
                .added(removed, changedAt: 11),
                .removed(statementAccountId: removed.statementAccountId, changedAt: 12)
            ],
            in: sender
        )
        let checkpoint = Date()

        try await transfer(after: nil)

        let rows = try await deviceRows(in: receiver)
        #expect(rows[kept.statementAccountId]?.status == .active)
        #expect(rows[kept.statementAccountId]?.changedAt == 10)
        #expect(rows[removed.statementAccountId]?.status == .inactive)
        #expect(rows[removed.statementAccountId]?.changedAt == 12)
        let contact = try await ContactsLocalStorageService(storageFacade: receiver, logger: MockLogger())
            .getContact(by: peer)
            .asyncExecute()
        #expect(contact?.devices == [kept])
        let echoed = try await DeviceSyncChatStateCollector(databaseService: receiver.databaseService)
            .collect(after: checkpoint)
        #expect(echoed.isEmpty)
    }

    @Test("An older synced device change doesn't overwrite the new phone's newer one")
    func olderSyncedDeviceChangeIsIgnored() async throws {
        let device = makeDevice(0x21)
        try await insertContact(in: sender)
        try await insertContact(in: receiver)
        try await updateDevices([.added(device, changedAt: 10)], in: sender)
        try await updateDevices(
            [.added(device, changedAt: 15), .removed(statementAccountId: device.statementAccountId, changedAt: 20)],
            in: receiver
        )

        try await transfer(after: nil)

        let row = try await deviceRows(in: receiver)[device.statementAccountId]
        #expect(row?.status == .inactive)
        #expect(row?.changedAt == 20)
    }

    @Test("A peer's acceptance applied from sync isn't sent back as an outgoing status update")
    func syncedAcceptanceIsNotEchoed() async throws {
        let message = Chat.RequestMessage(
            messageId: "outgoing",
            timestamp: 1_000,
            content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
        )
        let device = Chat.PeerDevice(
            statementAccountId: Data(repeating: 0x21, count: 32),
            encryptionPublicKey: Data(repeating: 0x22, count: 32)
        )
        try await insertOutgoingRequest(message, in: receiver)
        let checkpoint = Date()
        let contacts = ContactsLocalStorageService(storageFacade: receiver, logger: MockLogger())

        try await DeviceSyncChatAcceptedApplier(
            storageFacade: receiver,
            contactsStorageService: contacts,
            peerLogger: MockLogger()
        ).apply([makePeerAcceptance(requestId: message.messageId, device: device)])

        let echoed = try await DeviceSyncChatStateCollector(databaseService: receiver.databaseService)
            .collect(after: checkpoint)
        #expect(echoed.isEmpty)
        #expect(try await contacts.getContact(by: peer).asyncExecute()?.devices == [device])
    }
}

private extension DeviceSyncChatStateTests {
    struct DeviceRow {
        let status: Chat.ContactDeviceStatus?
        let changedAt: Int64
    }

    func makeDevice(_ byte: UInt8) -> Chat.PeerDevice {
        Chat.PeerDevice(
            statementAccountId: Data(repeating: byte, count: 32),
            encryptionPublicKey: Data(repeating: byte + 0x10, count: 32)
        )
    }

    func updateDevices(_ changes: [Chat.DeviceChange], in facade: UserDataStorageTestFacade) async throws {
        try await ContactsLocalStorageService(storageFacade: facade, logger: MockLogger())
            .updateDeviceSettings([Chat.ContactDeviceSettings(accountId: peer, changes: changes)])
            .asyncExecute()
    }

    func deviceRows(in facade: UserDataStorageTestFacade) async throws -> [Data: DeviceRow] {
        try await facade.databaseService.performRead { context in
            try context.fetch(CDContactDevice.fetchRequest()).reduce(into: [:]) { result, row in
                guard let statementAccountId = row.statementAccountId else { return }
                result[statementAccountId] = DeviceRow(
                    status: Chat.ContactDeviceStatus(rawValue: row.status),
                    changedAt: row.changedAt
                )
            }
        }
    }

    func makePeerAcceptance(requestId: String, device: Chat.PeerDevice) -> Chat.DeviceSyncWireMessage {
        Chat.DeviceSyncWireMessage(
            remote: Chat.RemoteMessage(
                messageId: "acceptance",
                timestamp: 2_000,
                versioned: .v1(Chat.RemoteMessageContentV1(
                    content: .multiChatAccepted(.init(requestId: requestId, device: device))
                ))
            ),
            peerId: peer,
            status: .incoming(.seen),
            order: 1
        )
    }

    func transfer(after cutoff: Date?) async throws {
        let entities = try await DeviceSyncChatStateCollector(databaseService: sender.databaseService)
            .collect(after: cutoff)
        let applier = makeApplier()

        for sentEntity in entities {
            let entity = try Chat.DeviceSyncEntity(scaleDecoder: ScaleDecoder(data: sentEntity.scaleEncoded()))

            switch entity {
            case let .chatsBlocked(states): try await applier.applyBlockStates(states)
            case let .incomingRequestsAdded(requests): try await applier.applyIncomingRequests(requests)
            case let .incomingRequestsStatusUpdated(updates): try await applier.applyIncomingStatusUpdates(updates)
            case let .outgoingRequestsAdded(requests): try await applier.applyOutgoingRequests(requests)
            case let .outgoingRequestsStatusUpdated(updates): try await applier.applyOutgoingStatusUpdates(updates)
            case let .contactDevicesChanged(changes): try await applier.applyContactDeviceChanges(changes)
            default: Issue.record("Unexpected entity \(entity.logLabel)")
            }
        }
    }

    func makeApplier() -> DeviceSyncChatStateApplier {
        DeviceSyncChatStateApplier(
            databaseService: receiver.databaseService,
            remoteContactResolver: MockRemoteContactResolver(result: .success(remoteContact)),
            tldProvider: StubDotNsTldProvider(tld: "dot"),
            logger: MockLogger()
        )
    }

    func ownKeyId() -> Chat.Contact.Own {
        Chat.Contact.Own(signKeyId: "//wallet//main", encryptionKeyId: "main")
    }

    func insertContact(in facade: UserDataStorageTestFacade) async throws {
        let contact = Chat.Contact(remoteContact: remoteContact, ownKeyId: ownKeyId())
        try await facade.createRepository(mapper: AnyCoreDataMapper(ChatContactMapper()))
            .saveOperation({ [contact] }, { [] })
            .asyncExecute()
    }

    func setBlocked(_ isBlocked: Bool, in facade: UserDataStorageTestFacade) async throws {
        let status = Chat.ContactBlockStatus(accountId: peer, isBlocked: isBlocked)
        try await facade.createRepository(mapper: AnyCoreDataMapper(BlockContactMapper()))
            .saveOperation({ [status] }, { [] })
            .asyncExecute()
    }

    func isBlocked(in facade: UserDataStorageTestFacade) async throws -> Bool {
        try await facade.databaseService.performRead { [peer] context in
            let contact: CDChatContact? = try context.first(for: .contact(for: peer))
            return contact?.isBlocked ?? false
        }
    }

    /// A decided request no longer links to a contact, as after the accept and decline mappers.
    func insertIncomingRequest(_ requestId: String, status: Chat.RequestStatus) async throws {
        try await sender.databaseService.performWrite { [peer] context in
            let request = try context.insertNew(CDChatRequest.self)
            request.identifier = requestId
            request.contactId = peer.toHex()
            request.timestamp = 1_000
            request.status = status.rawValue
            request.markModified()
        }
    }

    func insertOutgoingRequest(_ message: Chat.RequestMessage, in facade: UserDataStorageTestFacade) async throws {
        let newOutgoing = ChatRequest.NewOutgoing(
            message: message,
            remoteContact: remoteContact,
            pushId: nil,
            ownKeyId: ownKeyId()
        )
        try await facade.createRepository(mapper: AnyCoreDataMapper(NewOutgoingChatRequestMapper()))
            .saveOperation({ [newOutgoing] }, { [] })
            .asyncExecute()
    }

    func makeRequestStoreService() -> ChatRequestStoreService {
        ChatRequestStoreService(
            storageFacade: receiver,
            pushIdFactory: ChatPushIdFactory(
                encryptionManager: ChatEncryptionManager(entropyManager: FixedRootEntropyManager()),
                signManager: ChatSignerManager(entropyManager: FixedRootEntropyManager()),
                sessionIdFactory: PeerSessionIdFactory(),
                logger: MockLogger()
            ),
            deviceEncryptionKeyManager: StubDeviceEncryptionKeyManager()
        )
    }
}
