import Foundation
import KeyDerivation
import NovaCrypto
import Testing

@testable import polkadot_app

@Suite("Root decision routing")
struct RootRouterTests {
    @Test("theme selection precedes onboarding")
    func themeBeforeOnboarding() throws {
        let resolver = makeResolver(themeSelected: false, hasWallets: false, hasBackup: false, hasUsername: false)
        #expect(try resolver.resolve() == .selectTheme)
    }

    @Test("no wallets, no backup → onboarding")
    func onboarding() throws {
        let resolver = makeResolver(themeSelected: true, hasWallets: false, hasBackup: false, hasUsername: false)
        #expect(try resolver.resolve() == .onboarding)
    }

    @Test("no wallets, has backup → restore from cloud")
    func restoreFromCloud() throws {
        let resolver = makeResolver(themeSelected: true, hasWallets: false, hasBackup: true, hasUsername: false)
        #expect(try resolver.resolve() == .restoreFromCloud)
    }

    @Test("wallets without username → username check")
    func usernameCheck() throws {
        let resolver = makeResolver(themeSelected: true, hasWallets: true, hasBackup: false, hasUsername: false)
        #expect(try resolver.resolve() == .usernameCheck)
    }

    @Test("established user, web3 main → dashboard")
    func dashboard() throws {
        let resolver = makeResolver(
            themeSelected: true,
            hasWallets: true,
            hasBackup: false,
            hasUsername: true,
            web3: .main
        )
        #expect(try resolver.resolve() == .dashboard)
    }

    @Test("established user, web3 spa → spa")
    func web3Spa() throws {
        let resolver = makeResolver(
            themeSelected: true,
            hasWallets: true,
            hasBackup: false,
            hasUsername: true,
            web3: .spa
        )
        #expect(try resolver.resolve() == .web3SummitSpa)
    }

    @Test("web3 gate only reached after wallet and username gates pass")
    func web3RunsLast() throws {
        // The web3 gate would yield spa, but the user has no wallets — WalletGate wins first.
        let resolver = makeResolver(
            themeSelected: true,
            hasWallets: false,
            hasBackup: false,
            hasUsername: false,
            web3: .spa
        )
        #expect(try resolver.resolve() == .onboarding)
    }

    @Test("summit not started check runs before all other gates")
    func notStartedRunsFirst() throws {
        let resolver = makeResolver(
            themeSelected: false,
            hasWallets: false,
            hasBackup: false,
            hasUsername: false,
            start: .notStarted
        )
        #expect(try resolver.resolve() == .web3SummitNotStarted)
    }

    @Test("summit not started precedes ended gate")
    func notStartedPrecedesEnded() throws {
        let resolver = makeResolver(
            themeSelected: true,
            hasWallets: true,
            hasBackup: false,
            hasUsername: true,
            web3: .ended,
            start: .notStarted
        )
        #expect(try resolver.resolve() == .web3SummitNotStarted)
    }

    @Test("summit started lets other gates decide")
    func startedPassesThrough() throws {
        let resolver = makeResolver(
            themeSelected: true,
            hasWallets: true,
            hasBackup: false,
            hasUsername: true,
            start: .started
        )
        #expect(try resolver.resolve() == .dashboard)
    }

    @Test("summit ended check runs before all other gates")
    func endedRunsFirst() throws {
        let resolver = makeResolver(
            themeSelected: false,
            hasWallets: false,
            hasBackup: false,
            hasUsername: false,
            web3: .ended
        )

        let endedSuppressed = RootGate.Web3SummitEnded(gate: makeWeb3Gate(.ended)).evaluate() == nil
        let expected: RootDestination = endedSuppressed ? .selectTheme : .web3SummitEnded
        #expect(try resolver.resolve() == expected)
    }

    @Test("throwing keystore aborts resolution (interactor maps it to broken)")
    func keystoreThrowAborts() {
        let resolver = SequentialDecisionResolver<RootDestination>(
            gates: [
                RootGate.Theme(storage: FakeThemeStorage(selected: true)),
                RootGate.Wallet(
                    entropyManager: ThrowingEntropyManager(),
                    backupHelper: FakeBackupHelper(hasBackup: false)
                )
            ],
            fallback: .dashboard
        )
        #expect(throws: (any Error).self) {
            try resolver.resolve()
        }
    }

    private func makeResolver(
        themeSelected: Bool,
        hasWallets: Bool,
        hasBackup: Bool,
        hasUsername: Bool,
        web3: Web3SummitDestination = .main,
        start: Web3SummitStartGateMode = .started
    ) -> SequentialDecisionResolver<RootDestination> {
        SequentialDecisionResolver(
            gates: [
                RootGate.Web3SummitStart(modeProvider: FakeStartModeProvider(mode: start)),
                RootGate.Web3SummitEnded(gate: makeWeb3Gate(web3)),
                RootGate.Theme(storage: FakeThemeStorage(selected: themeSelected)),
                RootGate.Wallet(
                    entropyManager: FakeEntropyManager(hasWallets: hasWallets),
                    backupHelper: FakeBackupHelper(hasBackup: hasBackup)
                ),
                RootGate.Username(usernameStorage: FakeUsernameStorage(hasUsername: hasUsername)),
                RootGate.Web3Summit(gate: makeWeb3Gate(web3))
            ],
            fallback: .dashboard
        )
    }

    private func makeWeb3Gate(_ destination: Web3SummitDestination) -> Web3SummitGate {
        let mode: Web3SummitGateMode =
            switch destination {
            case .main: .verificationDisabled
            case .spa: .verificationEnabled
            case .ended: .ended
            }

        return Web3SummitGate(
            modeProvider: FakeModeProvider(mode: mode),
            verifiedStorage: FakeVerifiedStorage(verified: false)
        )
    }
}

private struct FakeThemeStorage: ThemeSelectionStoring {
    let selected: Bool
    var hasSelectedTheme: Bool { selected }
    func setSelected() {}
}

private struct FakeEntropyManager: RootEntropyManaging {
    let hasWallets: Bool
    func fetchRootEntropy() throws -> Data { Data() }
    func createRootEntropy(_: Data) throws {}
    func hasRootEntropy() throws -> Bool { hasWallets }
}

private struct ThrowingEntropyManager: RootEntropyManaging {
    private struct Failure: Error {}
    func fetchRootEntropy() throws -> Data { throw Failure() }
    func createRootEntropy(_: Data) throws { throw Failure() }
    func hasRootEntropy() throws -> Bool { throw Failure() }
}

private struct FakeBackupHelper: MnemonicBackupHelperProtocol {
    let hasBackup: Bool
    var isAvailable: Bool { true }
    var didChangeAvailabilityNotification: Notification.Name { .init("test.backup") }
    func checkForBackup() throws -> Bool { hasBackup }
    func saveMnemonic(_: IRMnemonicProtocol) throws {}
    func fetchMnemonic() throws -> IRMnemonicProtocol { throw FakeError.unused }
    func deleteMnemonic() throws {}

    private enum FakeError: Error { case unused }
}

private final class FakeUsernameStorage: UsernameStoring {
    var username: Username?
    var usernameClaimed = false
    var isPerson = false

    init(hasUsername: Bool) {
        username = hasUsername ? Username(value: "tester.01") : nil
    }
}

private struct FakeModeProvider: Web3SummitGateModeProviding {
    let mode: Web3SummitGateMode
    func current() -> Web3SummitGateMode { mode }
}

private struct FakeStartModeProvider: Web3SummitStartGateProviding {
    let mode: Web3SummitStartGateMode
    func current() -> Web3SummitStartGateMode { mode }
}

private final class FakeVerifiedStorage: Web3SummitVerifiedStoring {
    private var verified: Bool
    init(verified: Bool) { self.verified = verified }
    func isVerified() -> Bool { verified }
    func setVerified(_ value: Bool) { verified = value }
}
