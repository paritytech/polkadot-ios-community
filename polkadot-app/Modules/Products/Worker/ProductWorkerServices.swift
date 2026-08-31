import Foundation

/// Composition root for the product-worker ref counter and its operations.
///
/// One instance per app launch owns the shared `ProductWorkerManager` and
/// `ProductWorkerOperationService`, so every consumer (the chats screen, a
/// product's full-page screen, and host-api operations) ref-counts the same
/// per-product worker.
///
/// The worker-boot factory is installed at launch via ``configure(factory:)``,
/// because assembling a worker needs the product dependency graph, which is
/// built after this owner. Until then `lock`/`acquire` still ref-count, they
/// just start no JS worker.
final class ProductWorkerServices {
    static let shared = ProductWorkerServices()

    private let workerManager: ProductWorkerManager
    let operations: ProductWorkerOperating

    var manager: ProductWorkerManaging { workerManager }

    private init() {
        let manager = ProductWorkerManager()
        workerManager = manager
        let service = ProductWorkerOperationService(
            workerManager: manager,
            store: CoreDataProductOperationStore()
        )
        service.resetForNewSession()
        operations = service
    }

    /// Install the worker-boot factory. Call once at launch, before any screen
    /// that could lock a worker is shown.
    func configure(factory: ProductWorkerFactory) {
        workerManager.setFactory(factory)
    }
}
