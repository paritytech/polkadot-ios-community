import Foundation
import os
import StatementStore

final class RecordingStatementSignerManager: StatementStoreSignerManaging, @unchecked Sendable {
    private let keyIds = OSAllocatedUnfairLock<[String]>(initialState: [])

    var requestedKeyIds: [String] { keyIds.withLock { $0 } }

    func makeSigner(for signerKeyId: String) throws -> StatementStoreSigning {
        keyIds.withLock { $0.append(signerKeyId) }

        return StubStatementSigner(accountId: Data(signerKeyId.utf8))
    }
}
