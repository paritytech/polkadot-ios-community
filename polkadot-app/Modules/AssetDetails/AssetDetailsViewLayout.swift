import SwiftUI
import ExternalAccessibility
import PolkadotUI
import DesignSystem

struct AssetDetailsView: View {
    @State var viewModel: AssetDetailsViewModelProtocol
    var isExpanded: Bool = false
    var onCardTapped: () -> Void
    var onCollapse: (() -> Void)?

    init(
        viewModel: AssetDetailsViewModelProtocol = AssetDetailsViewModel(),
        isExpanded: Bool = false,
        onCardTapped: @escaping () -> Void,
        onCollapse: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.isExpanded = isExpanded
        self.onCardTapped = onCardTapped
        self.onCollapse = onCollapse
    }

    var body: some View {
        DSExpandableCardLayout(
            isExpanded: isExpanded,
            onCollapse: onCollapse,
            card: { headerCard },
            details: { expandedBody }
        )
        .safeAreaInset(edge: .bottom) {
            if !viewModel.fundingStates.isEmpty {
                AssetFundingStatusView(
                    states: $viewModel.fundingStates,
                    isExpanded: $viewModel.isFundingExpanded,
                    configuration: .fundingDigitalDollarConfiguration(
                        onCompletedAction: viewModel.onFundingCompleted,
                        onFailedAction: viewModel.onFundingFailed
                    )
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var headerCard: some View {
        if let balanceCardModel = viewModel.balanceCardModel {
            balanceCard(balanceCardModel)
                .onTapGesture { onCardTapped() }
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(spacing: 16) {
            #if TESTNET_FEATURE
                fixtureToggle()
            #endif
            if viewModel.showsBackupNotification {
                backupCard()
            } else {
                actions()
            }
            #if TESTNET_FEATURE
                HStack {
                    VStack { Divider().background(Color.fgPrimary) }
                    Text(verbatim: "Debug features")
                        .typography(.labelMedium)
                        .foregroundStyle(Color.fgPrimary)
                    VStack { Divider().background(Color.fgPrimary) }
                }

                testnetTopUpButton()
                if let breakdown = viewModel.coinageBreakdown,
                   viewModel.balanceCardModel != nil {
                    CoinageBalanceBreakdownView(
                        breakdown: breakdown,
                        onMakeAllVouchersReady: viewModel.onMakeAllVouchersReady
                    )
                }
            #endif
        }
    }

    private func balanceCard(
        _ balanceCardModel: AssetDetailsBalanceCard.ViewModel
    ) -> some View {
        AssetDetailsBalanceCard(
            viewModel: balanceCardModel,
            isUpdating: viewModel.isUpdating,
            isExpanded: isExpanded
        )
    }

    private func backupCard() -> some View {
        WalletBackupNotificationCard(
            isUpdating: viewModel.isUpdating,
            onSync: viewModel.onBackupSync,
            onCancel: viewModel.onBackupCancel,
            onWhyUpdate: viewModel.onBackupWhyUpdate
        )
    }

    private func actions() -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                DSButton(.actionSendCash, leadingIcon: .iconArrowUp16, expands: true) {
                    viewModel.onSendMoney?()
                }
                .accessibilityId(AccessibilityID.Wallet.sendPaymentButton)

                topUpButton()
            }
        }
    }

    private func topUpButton() -> some View {
        Button {
            viewModel.onTopUp?()
        } label: {
            Group {
                if viewModel.isTopUpInProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.fgPrimaryInverted)
                } else {
                    Image(.add24)
                        .renderingMode(.template)
                }
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.fgPrimaryInverted)
            .background(.bgActionPrimary, in: Circle())
        }
        .disabled(viewModel.isTopUpInProgress)
        .accessibilityId(AccessibilityID.Wallet.addFundsButton)
    }

    #if TESTNET_FEATURE
        private func fixtureToggle() -> some View {
            Button {
                viewModel.onToggleFixtureCoinage?()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Test data")
                            .textStyle(.body14Regular())
                        Text(
                            verbatim: viewModel.usesFixtureCoinage
                                ? "\(CoinageFixtures.coinCount) coins, \(CoinageFixtures.voucherCount) vouchers"
                                : "Using real holdings"
                        )
                        .textStyle(.caption12Regular())
                        .foregroundStyle(.fgSecondary)
                    }

                    Spacer()

                    Text(verbatim: viewModel.usesFixtureCoinage ? "ON" : "OFF")
                        .textStyle(.body14Regular())
                        .foregroundStyle(viewModel.usesFixtureCoinage ? Color.fgPrimaryInverted : .fgSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.usesFixtureCoinage ? Color.bgActionPrimary : .bgSurfaceMain,
                            in: Capsule()
                        )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.bgSurfaceNested, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.fgPrimary)
        }

        private func testnetTopUpButton() -> some View {
            Button {
                viewModel.onTestnetTopUp?()
            } label: {
                Group {
                    if viewModel.isTestnetTopUpInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.fgPrimaryInverted)
                    } else {
                        Text(verbatim: "Faucet Top Up")
                            .textStyle(.body14SemiBold())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Color.fgPrimaryInverted)
                .background(.bgActionPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isTestnetTopUpInProgress)
        }
    #endif
}

#if TESTNET_FEATURE
    private struct CoinageBalanceBreakdownView: View {
        let breakdown: CoinageBalanceBreakdownViewModel

        var onMakeAllVouchersReady: (() -> Void)?

        @State private var showDetails = false

        var body: some View {
            VStack(spacing: 12) {
                Text(verbatim: "Coinage Balance")
                    .textStyle(.title16SemiBold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityId(AccessibilityID.Wallet.coinageHeader)

                BreakdownRow(
                    title: "Total Balance",
                    value: breakdown.totalBalance,
                    labelAccessibilityId: AccessibilityID.Wallet.coinageTotalBalanceLabel,
                    valueAccessibilityId: AccessibilityID.Wallet.coinageTotalBalanceValue
                )
                BreakdownRow(
                    title: "Spendable Balance",
                    value: breakdown.spendableBalance,
                    labelAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceLabel,
                    valueAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceValue
                )
                BreakdownRow(
                    title: "Pending Balance",
                    value: breakdown.pendingBalance,
                    labelAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceLabel,
                    valueAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceValue
                )

                Divider()

                CoinageCompositionBar(model: breakdown.composition)
                    .padding(.vertical, 2)

                if let onMakeAllVouchersReady {
                    Button {
                        onMakeAllVouchersReady()
                    } label: {
                        Text(verbatim: "Make all vouchers ready")
                            .textStyle(.body14SemiBold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.fgPrimaryInverted)
                    }
                    .background(.bgActionPrimary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityId(AccessibilityID.Wallet.makeVouchersReadyButton)
                }

                Button {
                    withAnimation { showDetails.toggle() }
                } label: {
                    HStack {
                        Text(verbatim: showDetails ? "Hide Details" : "Show Details")
                            .textStyle(.body14SemiBold())
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.fgPrimary)
                }

                if showDetails {
                    CoinageDetailsView(breakdown: breakdown)
                }
            }
            .padding(16)
            .background(.bgSurfaceContainer, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private struct CoinageDetailsView: View {
        let breakdown: CoinageBalanceBreakdownViewModel

        var body: some View {
            VStack(spacing: 6) {
                ForEach(breakdown.holdings) { holding in
                    CoinageHoldingRow(holding: holding)
                }
            }
        }
    }

    private struct CoinageHoldingRow: View {
        let holding: CoinageHoldingViewModel

        /// Fixed, not intrinsic: every depiction has to start at the same x and share one column
        /// width, or the bar lengths would not be comparable between rows.
        private let amountColumnWidth: CGFloat = 52

        var body: some View {
            HStack(spacing: 10) {
                Text(verbatim: holding.amount ?? "—")
                    .textStyle(.body14Regular())
                    .foregroundStyle(.fgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: amountColumnWidth, alignment: .trailing)

                switch holding.status {
                case let .coin(model):
                    CoinStatusView(model: model)
                case let .voucher(model):
                    VoucherStatusView(model: model)
                }
            }
        }
    }

    private struct BreakdownRow: View {
        let title: String
        let value: String
        var labelAccessibilityId: (any AccessibilityIdentifying)?
        var valueAccessibilityId: (any AccessibilityIdentifying)?

        var body: some View {
            HStack {
                Text(title)
                    .textStyle(.body14Regular())
                    .foregroundStyle(.fgSecondary)
                    .accessibilityId(labelAccessibilityId)
                Spacer()
                Text(value)
                    .textStyle(.body14SemiBold())
                    .accessibilityId(valueAccessibilityId)
            }
        }
    }
#endif
