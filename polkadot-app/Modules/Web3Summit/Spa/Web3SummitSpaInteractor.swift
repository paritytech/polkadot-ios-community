import Foundation
import Foundation_iOS
import Individuality
import KeyDerivation
import Products
import SubstrateSdk

final class Web3SummitSpaInteractor {
    private let accountManager: ProductsAccountManaging
    private let contractRepository: Web3SummitContractRepositoryProtocol
    private let membershipStatusChecker: MembershipStatusChecking
    private let liteVrfManager: BandersnatchKeyManaging
    private let verifiedStorage: Web3SummitVerifiedStoring
    private let dotNsHost: String
    private let logger: LoggerProtocol

    init(
        accountManager: ProductsAccountManaging,
        contractRepository: Web3SummitContractRepositoryProtocol,
        membershipStatusChecker: MembershipStatusChecking,
        liteVrfManager: BandersnatchKeyManaging,
        verifiedStorage: Web3SummitVerifiedStoring,
        dotNsHost: String,
        logger: LoggerProtocol
    ) {
        self.accountManager = accountManager
        self.contractRepository = contractRepository
        self.membershipStatusChecker = membershipStatusChecker
        self.liteVrfManager = liteVrfManager
        self.verifiedStorage = verifiedStorage
        self.dotNsHost = dotNsHost
        self.logger = logger
    }
}

private extension Web3SummitSpaInteractor {
    func resolveIsCheckedIn(productAccountId: AccountId) async -> Bool {
        await (try? contractRepository.isCheckedIn(productAccountId: productAccountId)) ?? false
    }

    func checkMembership(memberKey: MembersPallet.RingMember) async throws -> Bool {
        let statuses = try await membershipStatusChecker.checkStatuses(
            of: [.init(memberKey: memberKey, collection: PeopleLitePallet.membersIdentifier)],
            blockHash: nil
        )

        return statuses[memberKey] != nil
    }

    func resolveStatus(
        productAccountId: AccountId,
        liteKey: MembersPallet.RingMember
    ) async -> Web3SummitAttendanceStatus {
        let checkedIn = await resolveIsCheckedIn(productAccountId: productAccountId)
        let included = await (try? checkMembership(memberKey: liteKey)) ?? false

        logger.debug("W3S isCheckedIn=\(checkedIn) liteIncluded=\(included)")

        switch (checkedIn, included) {
        case (false, _):
            return .notCheckedIn
        case (true, false):
            return .checkedIn
        case (true, true):
            return .confirmed
        }
    }

    func pollAttendance(onStatus: @Sendable (Web3SummitAttendanceStatus) -> Void) async throws {
        let productAccountId = try accountManager.deriveAccount(
            ProductAccountId(productId: dotNsHost, derivationIndex: 0)
        )
        let liteKey = try liteVrfManager.getMemberKey()

        var lastStatus: Web3SummitAttendanceStatus?

        while true {
            try Task.checkCancellation()

            let status = await resolveStatus(productAccountId: productAccountId, liteKey: liteKey)

            if status != lastStatus {
                lastStatus = status
                onStatus(status)
            }

            guard status != .confirmed else {
                verifiedStorage.setVerified(true)
                return
            }

            try await Task.sleep(for: .seconds(2))
        }
    }
}

extension Web3SummitSpaInteractor: Web3SummitSpaInteractorProtocol {
    func attendanceStatusUpdates() -> AsyncThrowingStream<Web3SummitAttendanceStatus, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    try await self?.pollAttendance { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func markVerifiedManually() {
        verifiedStorage.setVerified(true)
    }
}
