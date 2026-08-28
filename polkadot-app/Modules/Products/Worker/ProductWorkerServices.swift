import Foundation

/// Composition root for the product-worker ref counter and its operations.
///
/// One instance per app launch owns the shared `ProductWorkerManager` and
/// `ProductWorkerOperationService`, so every consumer (the chats screen, a
/// product's full-page screen, and host-api operations) ref-counts the same
/// per-product worker.
///
/// The worker-boot factory is left `nil` for now: ref-counting and operations
/// are wired and tested, while booting the real JS worker and unifying it with
/// the chat `ProductBot` is the remaining integration step.
final class ProductWorkerServices {
    static let shared = ProductWorkerServices()

    let manager: ProductWorkerManaging
    let operations: ProductWorkerOperating

    private init() {
        let manager = ProductWorkerManager(factory: nil)
        self.manager = manager
        let service = ProductWorkerOperationService(
            workerManager: manager,
            store: FileProductOperationStore()
        )
        service.resetForNewSession()
        operations = service
    }
}
