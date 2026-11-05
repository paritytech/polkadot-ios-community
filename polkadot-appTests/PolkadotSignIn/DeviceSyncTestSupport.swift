@testable import polkadot_app
import AsyncExtensions
import CoreData
import Foundation
import Foundation_iOS
import MessageExchangeKit
import Operation_iOS
import SubstrateSdk

extension DeviceSyncExchangeTests {
    func makeSession(
        peerAccountId: Data,
        flow: MockDeviceSyncPeerConnectionFlow,
        failureRecorder: DeviceSyncFailureRecorder? = nil,
        remoteContactResolver: RemoteContactResolving = MockRemoteContactResolver(result: .success(nil)),
        deviceRepositoryFactory: LocalDeviceRepositoryMaking = MockLocalDeviceRepositoryFactory(),
        contactRepositoryFactory: ChatContactRepositoryMaking = MockChatContactRepositoryFactory(),
        messageRepositoryFactory: ChatMessageRepositoryMaking = MockChatMessageRepositoryFactory(),
        removedChatRepositoryFactory: RemovedChatRepositoryMaking = MockRemovedChatRepositoryFactory(),
        outgoingUpdateTimeRepositoryFactory: OutgoingUpdateTimeRepositoryMaking =
            MockOutgoingUpdateTimeRepositoryFactory(),
        ackTimeout: Duration = .seconds(3_600),
        sleep: @escaping DeviceSyncSleep = liveDeviceSyncSleep,
        entityChunker: DeviceSyncEntityChunker = .init(),
        fileTransferFactory: (any DeviceSyncFileTransferMaking)? = nil
    ) -> DeviceSyncExchange {
        let storageFacade = UnusedDeviceSyncStorageFacade()

        return DeviceSyncExchange(
            peer: .init(statementAccountId: peerAccountId, initialCheckpoint: nil),
            flow: flow,
            dependencies: .init(
                remoteContactResolver: remoteContactResolver,
                deviceRepositoryFactory: deviceRepositoryFactory,
                contactRepositoryFactory: contactRepositoryFactory,
                chatRepositoryFactory: MockChatRepositoryFactory(),
                messageRepositoryFactory: messageRepositoryFactory,
                removedChatRepositoryFactory: removedChatRepositoryFactory,
                outgoingUpdateTimeRepositoryFactory: outgoingUpdateTimeRepositoryFactory,
                contactDataProviderFactory: MockChatContactDataProviderFactory(),
                messageDataProviderFactory: MockChatMessageDataProviderFactory(),
                ownSignKeyIds: [WalletDerivationPath.main(for: "dot")],
                contactsStorageService: ContactsLocalStorageService(
                    storageFacade: storageFacade,
                    logger: MockLogger()
                ),
                storageFacade: storageFacade,
                updateIdProvider: MockDeviceSyncUpdateIdProvider(),
                chatStateCollector: EmptyChatStateCollector(),
                chatStateApplier: EmptyChatStateApplier(),
                coinageStateCollector: EmptyCoinageStateCollector(),
                coinageStateApplier: EmptyCoinageStateApplier(),
                fileTransferFactory: fileTransferFactory
            ),
            peerLogger: MockLogger(),
            behavior: .init(
                ackTimeout: ackTimeout,
                sleep: sleep,
                entityChunker: entityChunker
            ),
            handlers: .init(
                failure: { failure in
                    await failureRecorder?.record(accountId: peerAccountId, failure: failure)
                }
            )
        )
    }
}

private final class UnusedDeviceSyncStorageFacade: StorageFacadeProtocol {
    var databaseService: CoreDataServiceProtocol {
        fatalError("Storage is not used by these device sync tests")
    }

    func createRepository<T, U>(
        filter _: NSPredicate?,
        sortDescriptors _: [NSSortDescriptor],
        mapper _: AnyCoreDataMapper<T, U>
    ) -> CoreDataRepository<T, U> where T: Identifiable, U: NSManagedObject {
        fatalError("Storage is not used by these device sync tests")
    }
}

private struct EmptyChatStateCollector: DeviceSyncChatStateCollecting {
    func collect(after _: Date?) async throws -> [Chat.DeviceSyncEntity] { [] }
}

private struct EmptyChatStateApplier: DeviceSyncChatStateApplying {
    func applyBlockStates(_: [Chat.DeviceSyncChatBlockState]) async throws {}
    func applyIncomingRequests(_: [Chat.DeviceSyncIncomingChatRequest]) async throws {}
    func applyIncomingStatusUpdates(_: [Chat.DeviceSyncIncomingRequestStatusUpdate]) async throws {}
    func applyOutgoingRequests(_: [Chat.DeviceSyncOutgoingChatRequest]) async throws {}
    func applyOutgoingStatusUpdates(_: [Chat.DeviceSyncOutgoingRequestStatusUpdate]) async throws {}
}

private struct EmptyCoinageStateCollector: DeviceSyncCoinageStateCollecting {
    func collect(after _: Date?) async throws -> [Chat.DeviceSyncEntity] { [] }
}

private struct EmptyCoinageStateApplier: DeviceSyncCoinageStateApplying {
    func applyHandedOffCoins(_: [Chat.DeviceSyncHandedOffCoin]) async throws {}
    func applyClaimStatuses(_: [Chat.DeviceSyncCoinageMessageStatusUpdate]) async throws {}
}
