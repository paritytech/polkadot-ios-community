import Foundation
import Products

// MARK: - Account & Chain

extension ProductsNativeApi {
    func accountGet(_ accountId: ProductAccountId) async throws -> ProductAccountResult {
        guard try await permissionGuard.consumePermission(
            productId: productId,
            permission: .accountAccess(targetProductId: accountId.productId)
        ) else {
            throw ProductNativeApiError.permissionDenied
        }

        let publicKey = try accountManager.deriveAccount(accountId)
        return ProductAccountResult(
            publicKey: publicKey.toHex(includePrefix: true)
        )
    }

    func getUserId() async throws -> GetUserIdResult {
        guard let username = usernameStorage.username else {
            throw ProductNativeApiError.notConnected
        }

        guard try await permissionGuard.consumePermission(
            productId: productId,
            permission: .userIdentityAccess
        ) else {
            throw ProductNativeApiError.permissionDenied
        }

        return GetUserIdResult(primaryUsername: username.value)
    }

    func accountGetAlias(_ accountId: ProductAccountId) async throws -> AccountGetAliasResult {
        let aliasResult = try accountManager.deriveAlias(accountId)
        return AccountGetAliasResult(
            context: aliasResult.context.toHex(includePrefix: true),
            alias: aliasResult.alias.toHex(includePrefix: true)
        )
    }

    func getNonProductAccounts() async throws -> [LegacyAccountResult] {
        try nonProductAccountRegistry.getPublicKeys().map { publicKey in
            LegacyAccountResult(
                publicKey: publicKey.toHex(includePrefix: true),
                name: usernameStorage.username?.value
            )
        }
    }

    func chainNodes(genesisHash: String) async throws -> [String] {
        let genesis = genesisHash.withoutHexPrefix()

        guard let chain = chainRegistry.getChainByGenesis(for: genesis) else {
            return []
        }

        return chain.nodes.map(\.url)
    }

    func chainSupported(genesisHash: String) async throws -> Bool {
        let genesis = genesisHash.withoutHexPrefix()

        return chainRegistry.getChainByGenesis(for: genesis) != nil
    }
}
