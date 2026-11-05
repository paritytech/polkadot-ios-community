@testable import polkadot_app
import Foundation
import Keystore_iOS
import os
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferFinalizerTests {
    private let store = MockStatementStore()
    private let processedStore = DeviceTransferProcessedCoreDataStore(storageFacade: UserDataStorageTestFacade())
    private let checkpointStore = DeviceTransferCheckpointStore(settingsManager: InMemorySettingsManager())
    private let request = DeviceTransferRequest(
        requestId: "request",
        deviceModel: "iPhone 17 Pro",
        operatingSystem: "iOS 26.1",
        createdAt: 1_700_000_000_000
    )
    private let oldPhoneId = Data(repeating: 0x01, count: 32)
    private let newPhoneId = Data(repeating: 0x02, count: 32)

    init() {
        checkpointStore.save(5_000, senderInstallationId: oldPhoneId)
    }

    @Test("Finalize makes the new phone active and the old one inactive, then drops the transfer's leftovers")
    func finalizeHandsOverActiveStatus() async throws {
        let dates = MockDateProvider()
        let oldPhone = makeInstallationService(installationId: oldPhoneId, dates: dates)
        await oldPhone.setup(configuration: configuration())
        _ = await status(of: oldPhone) { $0 == .active }
        await dates.advance(by: 10)
        let newPhone = makeInstallationService(installationId: newPhoneId, dates: dates)
        await newPhone.setup(configuration: configuration())
        _ = await status(of: newPhone) { $0 != .unknown }

        try await makeFinalizer(publisher: newPhone).finalize(after: request)

        #expect(await status(of: newPhone) { $0 == .active } == .active)
        let oldPhoneStatus = await status(of: oldPhone) { $0 != .active }
        guard case let .inactive(record) = oldPhoneStatus else {
            Issue.record("Expected the old phone inactive, got \(String(describing: oldPhoneStatus))")
            return
        }
        #expect(record.installationId == newPhoneId)
        #expect(try await processedStore.processedRequestIds(among: [request.requestId]) == [request.requestId])
        #expect(checkpointStore.checkpoint(for: oldPhoneId) == nil)
    }

    @Test("A publish that fails at first is retried until it lands")
    func failedPublishIsRetried() async throws {
        let publisher = ScriptedPublisher(failures: Array(repeating: URLError(.timedOut), count: 2))

        try await makeFinalizer(publisher: publisher).finalize(after: request)

        #expect(publisher.attempts == 3)
        #expect(checkpointStore.checkpoint(for: oldPhoneId) == nil)
    }

    @Test("A publish that keeps failing fails finalize and keeps the checkpoint and the request")
    func exhaustedPublishKeepsCheckpoint() async throws {
        let publisher = ScriptedPublisher(failures: Array(repeating: URLError(.timedOut), count: 3))

        await #expect(throws: URLError.self) {
            try await makeFinalizer(publisher: publisher).finalize(after: request)
        }

        #expect(publisher.attempts == 3)
        #expect(checkpointStore.checkpoint(for: oldPhoneId) == 5_000)
        #expect(try await processedStore.processedRequestIds(among: [request.requestId]).isEmpty)
    }

    @Test("An installation service that was never set up fails finalize without retrying")
    func unconfiguredServiceIsNotRetried() async throws {
        let publisher = ScriptedPublisher(failures: [ActiveInstallationServiceError.notConfigured])

        await #expect(throws: ActiveInstallationServiceError.self) {
            try await makeFinalizer(publisher: publisher).finalize(after: request)
        }

        #expect(publisher.attempts == 1)
    }
}

private extension DeviceTransferFinalizerTests {
    func makeFinalizer(publisher: ActiveInstallationPublishing) -> DeviceTransferFinalizer {
        DeviceTransferFinalizer(
            installationPublisher: publisher,
            processedStore: processedStore,
            checkpointStore: checkpointStore,
            settings: DeviceTransferFinalizerSettings(publishAttempts: 3, publishRetryDelay: .zero),
            logger: MockLogger()
        )
    }

    func makeInstallationService(installationId: Data, dates: MockDateProvider) -> ActiveInstallationService {
        ActiveInstallationService(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(
                entropyManager: FixedRootEntropyManager(entropy: Data(repeating: 0x01, count: 16))
            ),
            installationProvider: FixedInstallationProvider(installationId: installationId),
            publishSettings: ActiveInstallationPublishSettings(
                deviceInfo: DeviceInfo(model: "iPhone 17 Pro", operatingSystem: "iOS 26.1")
            ),
            dateProvider: dates,
            logger: MockLogger()
        )
    }

    func configuration() -> ActiveInstallationConfiguration {
        ActiveInstallationConfiguration(
            connection: store,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        )
    }

    func status(
        of service: ActiveInstallationService,
        matching predicate: @escaping (InstallationStatus) -> Bool
    ) async -> InstallationStatus? {
        do {
            for try await status in await service.statusStream where predicate(status) {
                return status
            }
        } catch {
            Issue.record("Status stream failed: \(error)")
        }
        return nil
    }
}

private struct FixedInstallationProvider: CurrentInstallationProviding {
    let installationId: Data

    func currentInstallationId() async throws -> Data {
        installationId
    }
}

private final class ScriptedPublisher: ActiveInstallationPublishing {
    private let state: OSAllocatedUnfairLock<(failures: [Error], attempts: Int)>

    init(failures: [Error]) {
        state = OSAllocatedUnfairLock(uncheckedState: (failures, 0))
    }

    var attempts: Int {
        state.withLockUnchecked { $0.attempts }
    }

    func publishSelf() async throws {
        let failure: Error? = state.withLockUnchecked { state in
            state.attempts += 1
            return state.failures.isEmpty ? nil : state.failures.removeFirst()
        }

        if let failure {
            throw failure
        }
    }
}
