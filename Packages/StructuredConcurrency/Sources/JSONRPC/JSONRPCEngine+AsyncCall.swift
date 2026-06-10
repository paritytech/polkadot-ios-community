import Foundation
import SubstrateSdk

public extension JSONRPCEngine {
    func asyncCallMethod<R: Decodable>(
        _ method: String,
        params: (some Encodable)?,
        options: JSONRPCOptions
    ) async throws -> R {
        let mutex = NSLock()
        var callId: UInt16? = nil

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                mutex.lock()

                defer {
                    mutex.unlock()
                }

                do {
                    callId = try self.callMethod(
                        method,
                        params: params,
                        options: options
                    ) { result in
                        mutex.lock()

                        defer {
                            mutex.unlock()
                        }

                        guard callId != nil else {
                            return
                        }

                        callId = nil

                        continuation.resume(with: result)
                    }
                } catch {
                    callId = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            mutex.lock()

            defer {
                mutex.unlock()
            }

            if let cancellationIdentifier = callId {
                callId = nil
                cancelForIdentifier(cancellationIdentifier)
            }
        }
    }

    func asyncCallVoidMethod(
        _ method: String,
        params: (some Encodable)?,
        options: JSONRPCOptions
    ) async throws {
        // substrate sdk currently requires Decodable response but still handles empty result internally
        let _: String? = try await asyncCallMethod(method, params: params, options: options)
    }
}
