import Foundation
import FoundationExt
import SubstrateSdk

@testable import SubstrateOperation

struct RawArg: ScaleEncodable {
    let byte: UInt8

    init(_ byte: UInt8) { self.byte = byte }

    func encode(scaleEncoder: ScaleEncoding) throws {
        scaleEncoder.appendRaw(data: Data([byte]))
    }
}

final class MutableClock: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date) { current = now }

    func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        current = date
    }

    func read() async -> Date {
        snapshot()
    }

    private func snapshot() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }
}

/// Records how often the executor is hit and returns a distinct value per call by default, so a
/// cache hit (no new call) is observable as an unchanged value and call count.
final class SpyViewFunctionExecutor: ViewFunctionExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// The value returned for the Nth call (1-based). Distinct per call by default. The caller owns
    /// the concrete type here — it must match the `T` the fetch is decoded into.
    private let valueForCall: @Sendable (Int) -> Any

    init(valueForCall: @escaping @Sendable (Int) -> Any = { UInt32($0) }) {
        self.valueForCall = valueForCall
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func call<T: Decodable>(
        viewFunction _: ViewFunctionCodingPath,
        chainId _: ChainId,
        args _: [ScaleEncodable]
    ) async throws -> T {
        let index = recordCall()

        guard let typed = valueForCall(index) as? T else {
            throw SpyError.typeMismatch
        }
        return typed
    }

    private func recordCall() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }
}

enum SpyError: Error {
    case typeMismatch
}
