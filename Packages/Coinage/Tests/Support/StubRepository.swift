import Foundation
import Operation_iOS
@testable import Coinage

/// A `BaseOperation` that resolves immediately to a fixed value.
final class ResultOperation<T>: BaseOperation<T>, @unchecked Sendable {
    let value: T

    init(value: T) {
        self.value = value
        super.init()
    }

    override func main() {
        result = .success(value)
    }
}

/// Minimal in-memory repository for tests that only need a repository to exist. Fetches return the
/// seeded models; saves and deletes are no-ops.
final class StubRepository<T: Identifiable>: DataProviderRepositoryProtocol, @unchecked Sendable {
    typealias Model = T
    let models: [T]

    init(models: [T] = []) {
        self.models = models
    }

    func fetchOperation(
        by modelIdClosure: @escaping () throws -> String,
        options _: RepositoryFetchOptions
    ) -> BaseOperation<T?> {
        ResultOperation(value: (try? modelIdClosure()).flatMap { id in
            models.first { $0.identifier == id }
        })
    }

    func fetchAllOperation(with _: RepositoryFetchOptions) -> BaseOperation<[T]> {
        ResultOperation(value: models)
    }

    func fetchOperation(by _: RepositorySliceRequest, options _: RepositoryFetchOptions) -> BaseOperation<[T]> {
        ResultOperation(value: models)
    }

    func saveOperation(_: @escaping () throws -> [T], _: @escaping () throws -> [String]) -> BaseOperation<Void> {
        ResultOperation(value: ())
    }

    func replaceOperation(_: @escaping () throws -> [T]) -> BaseOperation<Void> {
        ResultOperation(value: ())
    }

    func fetchCountOperation() -> BaseOperation<Int> {
        ResultOperation(value: models.count)
    }

    func deleteAllOperation() -> BaseOperation<Void> {
        ResultOperation(value: ())
    }
}
