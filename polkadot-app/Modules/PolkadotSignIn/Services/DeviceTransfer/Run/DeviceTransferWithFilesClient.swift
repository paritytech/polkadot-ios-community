import Foundation

final class DeviceTransferWithFilesClient: DeviceTransferClientProtocol {
    private let inner: any DeviceTransferClientProtocol
    private let fileTransfer: any DeviceSyncFileTransferring

    init(inner: any DeviceTransferClientProtocol, fileTransfer: any DeviceSyncFileTransferring) {
        self.inner = inner
        self.fileTransfer = fileTransfer
    }

    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws {
        await fileTransfer.start()

        do {
            try await inner.run(onEvent: onEvent)
            await fileTransfer.close()
        } catch {
            await fileTransfer.close()
            throw error
        }
    }
}
