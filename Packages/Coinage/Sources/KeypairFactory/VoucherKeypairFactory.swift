import KeyDerivation
import SubstrateSdk
import NovaCrypto

public protocol VoucherKeyDeriving: CoinageKeypairFactory where Model == Voucher {
    /// Creates a key manager for a specific voucher to perform Bandersnatch operations (proofs, signing, aliases).
    func createKeyManager(for model: Model) throws -> any BandersnatchKeyManaging
}

extension VoucherKeyDeriving {
    func derivePublicKey(placeholderIndex index: UInt32) throws -> PublicKey {
        let placeholder = Voucher(
            exponent: 0,
            derivationIndex: UInt32(index),
            allocatedAt: .now,
            readyAt: .distantPast
        )
        return try derivePublicKey(for: placeholder)
    }
}

enum VoucherEntropyDerivingError: Error {
    case invalidDerivationPath
}

public final class VoucherKeypairFactory: BaseKeypairFactory<Voucher> {
    public init(entropyManager: RootEntropyManaging) {
        super.init(basePath: "//pps//ring-vrf", entropyManager: entropyManager)
    }

    override public func derivePublicKey(for model: Voucher) throws -> PublicKey {
        try createKeyManager(for: model).getMemberKey()
    }
}

extension VoucherKeypairFactory: VoucherKeyDeriving {
    public func createKeyManager(for model: Voucher) throws -> any BandersnatchKeyManaging {
        let path = derivationPath(for: model)
        return BandersnatchKeyManager(
            entropyDeriver: VoucherEntropyDeriving(path: path),
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
