import KeyDerivation
import SubstrateSdk
import NovaCrypto

public protocol VoucherKeyDeriving: CoinageKeypairFactory where Model == Voucher {
    /// Creates a key manager for a voucher index to perform Bandersnatch operations (proofs, signing, aliases).
    func createKeyManager(index: DerivationIndex) throws -> any BandersnatchKeyManaging
}

public extension VoucherKeyDeriving {
    /// Convenience over ``createKeyManager(index:)`` for a model whose index it reads.
    func createKeyManager(for model: Model) throws -> any BandersnatchKeyManaging {
        try createKeyManager(index: model.derivationIndex)
    }
}

enum VoucherEntropyDerivingError: Error {
    case invalidDerivationPath
}

public final class VoucherKeypairFactory: BaseKeypairFactory<Voucher> {
    public init(entropyManager: RootEntropyManaging) {
        super.init(basePath: "//pps//ring-vrf", entropyManager: entropyManager)
    }

    override public func derivePublicKey(index: DerivationIndex) throws -> PublicKey {
        try createKeyManager(index: index).getMemberKey()
    }
}

extension VoucherKeypairFactory: VoucherKeyDeriving {
    public func createKeyManager(index: DerivationIndex) throws -> any BandersnatchKeyManaging {
        BandersnatchKeyManager(
            entropyDeriver: VoucherEntropyDeriving(path: derivationPath(index: index)),
            entropyManager: entropyManager
        )
    }
}

// MARK: -

final class VoucherEntropyDeriving: BandersnatchEntropyDeriving {
    private let path: String
    private lazy var junctionFactory: JunctionFactoryProtocol = SubstrateJunctionFactory()

    init(path: String) {
        self.path = path
    }

    func deriveEntropy(from seed: Data) throws -> Data {
        let junctionResult = try junctionFactory.parse(path: path)
        let chaincodes = junctionResult.chaincodes
        guard !chaincodes.contains(where: { $0.type != .hard }) else {
            throw VoucherEntropyDerivingError.invalidDerivationPath
        }

        return try chaincodes.reduce(seed) { partialResult, chainCode in
            try partialResult.blake2b32WithKey(chainCode.data)
        }
    }
}
