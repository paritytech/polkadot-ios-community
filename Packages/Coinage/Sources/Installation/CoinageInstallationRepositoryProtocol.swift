import Foundation

/// A coinage derivation subtree this account is known to own but did not allocate on this device: it
/// is only ever scanned for balance, and the scan progress belongs to it.
public struct PreviousInstallation: Hashable, Sendable {
    public let id: CoinageInstallationId
    public let coinScanNextIndex: UInt32
    public let voucherScanNextIndex: UInt32
    public let initialScanCompleted: Bool

    public init(
        id: CoinageInstallationId,
        coinScanNextIndex: UInt32,
        voucherScanNextIndex: UInt32,
        initialScanCompleted: Bool
    ) {
        self.id = id
        self.coinScanNextIndex = coinScanNextIndex
        self.voucherScanNextIndex = voucherScanNextIndex
        self.initialScanCompleted = initialScanCompleted
    }
}

/// The installations this account owns: the current one, which is the only one new keys are allocated
/// in, and the previous ones the data store lists. Implemented in the app over CoreData.
public protocol CoinageInstallationRepositoryProtocol: Sendable {
    /// The current installation, created on first call. Concurrent first callers on a fresh install all
    /// get the same id — two current installations would split one device's keys across two subtrees.
    func getOrCreateCurrent() async throws -> CoinageInstallationId

    /// Records installations as previous ones, skipping the current one and any already known.
    func addPrevious(_ installations: [CoinageInstallationId]) async throws

    func getPrevious() async throws -> [PreviousInstallation]

    func updateCoinScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws

    func updateVoucherScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws

    func markInitialScanCompleted(_ installation: CoinageInstallationId) async throws
}

/// Reads the highest item allocated under an installation, so an allocator can hand out the next one.
public protocol CoinageKeyIndexQuerying: Sendable {
    func maxCoinItem(in installation: CoinageInstallationId) async throws -> UInt32?
    func maxVoucherItem(in installation: CoinageInstallationId) async throws -> UInt32?
}
