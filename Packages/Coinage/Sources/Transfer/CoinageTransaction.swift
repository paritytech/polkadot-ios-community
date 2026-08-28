import Foundation

/// The assets one durability entry consumes and mints, plus the coins handed to a peer.
///
/// `outputs` is the derivation-ref view used to register the entry; `outputCoins` is the same set
/// as full rows, used both to persist the projected mint and to build the on-chain call.
struct CoinageTransactionAssets {
    let inputs: [DurabilityInput]
    let outputs: [OwnAsset]
    let outputCoins: [Coin]
    let handedOff: [Coin]
}

/// Creates a fresh ``CoinageTransaction`` per durability entry.
protocol CoinageTransactionFactoryProtocol: Sendable {
    func newTransaction() -> CoinageTransaction
}

struct CoinageTransactionFactory: CoinageTransactionFactoryProtocol {
    let coinAllocator: any CoinAllocating

    func newTransaction() -> CoinageTransaction {
        CoinageTransaction(coinAllocator: coinAllocator)
    }
}

/// Collects what one coinage transaction consumes, mints, and hands off — allocating fresh coins as
/// it mints. A strategy declares its shape once ("consume this, mint that, hand these over") instead
/// of assembling parallel input, output, and handoff lists by hand and keeping them in step.
///
/// It writes no status: the ledger records the transaction, and until it does nothing here has been
/// committed to. Minting allocates a derivation index and records the coin as an output; the rows
/// themselves are persisted separately via the transfer context.
final class CoinageTransaction {
    private let coinAllocator: any CoinAllocating
    private var inputs: [DurabilityInput] = []
    private var outputCoins: [Coin] = []
    private var handedOff: [Coin] = []

    init(coinAllocator: any CoinAllocating) {
        self.coinAllocator = coinAllocator
    }

    /// Mints fresh coins for `exponents` — allocates each and records it as an output.
    func mintCoins(_ exponents: [Int16]) async throws -> [Coin] {
        var minted: [Coin] = []
        for exponent in exponents {
            try await minted.append(coinAllocator.allocate(exponent: exponent))
        }
        outputCoins += minted
        return minted
    }

    /// Consume coins this wallet minted, addressed by derivation index.
    func consume(coins: [Coin]) {
        inputs += coins.map { .coin(.own($0.derivationIndex)) }
    }

    /// Consume a coin received from a peer, addressed by the public key it was sent to.
    func consume(receivedPublicKey: Data) {
        inputs.append(.coin(.received(receivedPublicKey)))
    }

    /// Consume recycler vouchers, addressed by derivation index.
    func use(vouchers: [Voucher]) {
        inputs += vouchers.map { .recyclerVoucher($0.derivationIndex) }
    }

    /// Record coins as given to a peer.
    func handOff(coins: [Coin]) {
        handedOff += coins
    }

    func build() -> CoinageTransactionAssets {
        CoinageTransactionAssets(
            inputs: inputs,
            outputs: outputCoins.map { .coin($0.derivationIndex) },
            outputCoins: outputCoins,
            handedOff: handedOff
        )
    }
}
