import Foundation

/// Serializes status read-modify-write sections so concurrent writers cannot act
/// on a stale read. A plain actor is insufficient (reentrancy releases isolation
/// at every `await`), so work is chained tail-to-tail.
actor StatusUpdateSerializer {
    private var tail: Task<Void, Never> = Task {}

    func run<T: Sendable>(_ work: @Sendable @escaping () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<Result<T, Error>, Never> {
            await previous.value
            do {
                return try await .success(work())
            } catch {
                return .failure(error)
            }
        }
        tail = Task { _ = await task.value }
        return try await task.value.get()
    }
}
