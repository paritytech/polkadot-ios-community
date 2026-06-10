import Foundation
import SubstrateSdk
import AsyncExtensions
import StatementStore

/// Native capabilities exposed to product scripts via the container bridge.
public protocol ProductsNativeApiProtocol: AnyObject {
    func accountGet(_ accountId: ProductAccountId) async throws -> ProductAccountResult
    func accountGetAlias(_ accountId: ProductAccountId) async throws -> AccountGetAliasResult
    func chainNodes(genesisHash: String) async throws -> [String]
    func chainSupported(genesisHash: String) async throws -> Bool
    func sendMessage(_ message: ProductBotMessage, roomId: String?) async throws -> String
    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResult
    func subscribeRooms() async throws -> AnyAsyncSequence<[RoomInfo]>
    func getNonProductAccounts() async throws -> [LegacyAccountResult]
    func signPayload(_ payload: SignTransactionPayload) async throws -> SignResult
    func signRaw(_ payload: SigningRawPayload) async throws -> SignResult
    func createTransaction(_ payload: CreateTransactionPayload<ProductAccountId>) async throws
        -> CreateTransactionResult
    func localStorageRead(key: String) async throws -> String?
    func localStorageWrite(key: String, value: String) async throws
    func localStorageClear(key: String) async throws
    func navigateTo(destination: String) async throws
    func allowNetworkAccess(url: String) async throws -> Bool

    // Preimage
    func lookupPreimage(hash: Data) async throws -> Data
    func submitPreimage(data: Data) async throws -> String

    // Permissions
    func requestDevicePermission(capability: String) async throws -> Bool
    func requestRemotePermissions(_ requests: [RemotePermissionRequest]) async throws -> Bool

    // Statement Store
    func subscribeStatements(filter: TopicFilter) throws -> AnyAsyncSequence<StatementsPageDto>

    func createStatementProof(_ request: CreateStatementProofDto) async throws -> StatementProofDto

    func createStatementProofAuthorized(
        _ request: CreateStatementProofAuthorizedDto
    ) async throws -> StatementProofDto

    func submitStatement(_ statement: StatementDto) async throws

    // Payments
    func subscribePaymentBalance() async throws -> AnyAsyncSequence<PaymentBalance>
    func requestPayment(amountInPlanks: String, destination: AccountId) async throws -> PaymentReceipt
    func subscribePaymentStatus(paymentId: String) async throws -> AnyAsyncSequence<HostPaymentStatus>

    func paymentTopUp(amount: Balance, source: PaymentTopUpSource) async throws

    // Push Notification
    func pushNotification(_ request: ScheduledNotificationRequest) async throws -> UInt32
    func cancelPushNotification(identifier: UInt32) async throws

    // Entropy Derivation
    func deriveEntropy(key: Data) async throws -> Data

    // Resource Allocation
    func requestResourceAllocation(
        resources: [AllocatableResource]
    ) async throws -> [AllocationOutcome]

    func getUserId() async throws -> GetUserIdResult

    // Theme
    func subscribeTheme() async -> AnyAsyncSequence<ProductTheme>
}

// MARK: - Account

public struct ProductAccountResult {
    public let publicKey: String

    public init(publicKey: String) {
        self.publicKey = publicKey
    }
}

public struct LegacyAccountResult {
    public let publicKey: String
    public let name: String?

    public init(publicKey: String, name: String?) {
        self.publicKey = publicKey
        self.name = name
    }
}

public struct GetUserIdResult {
    public let primaryUsername: String

    public init(primaryUsername: String) {
        self.primaryUsername = primaryUsername
    }
}

// MARK: - Theme

public struct ProductTheme: Equatable {
    public enum Variant: String {
        case light = "Light"
        case dark = "Dark"
    }

    public let name: String
    public let variant: Variant

    public init(name: String, variant: Variant) {
        self.name = name
        self.variant = variant
    }
}

public struct AccountGetAliasResult {
    public let context: String
    public let alias: String

    public init(context: String, alias: String) {
        self.context = context
        self.alias = alias
    }
}

// MARK: - Messages

public enum ProductBotMessage {
    case text(String)
    case custom(messageType: String, data: Data)
}

// MARK: - Signing

public struct SigningRawPayload {
    public let account: ProductAccountId
    public let content: RawPayloadContent

    public init(account: ProductAccountId, content: RawPayloadContent) {
        self.account = account
        self.content = content
    }
}

public enum RawPayloadContent {
    case bytes(Data)
    case payload(String)
}

public struct SignResult {
    public let signature: String
    public let signedTx: String?

    public init(signature: String, signedTx: String?) {
        self.signature = signature
        self.signedTx = signedTx
    }
}
