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
            if viewModel.showsBackupNotification {
                backupCard()
            } else {
                actions()
            }
            if let breakdown = viewModel.coinageBreakdown,
               viewModel.balanceCardModel != nil {
                CoinageBalanceBreakdownView(
                    breakdown: breakdown,
                    onMakeAllVouchersReady: viewModel.onMakeAllVouchersReady
                )
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
            #endif
        }
        // The expanded card is sized to the whole screen, so the bottom of its content lands under
        // the tab bar chrome, which is an overlay: content there is drawn but cannot be tapped. The
        // chrome's inset does not reach this hierarchy, so clear it explicitly from the height the
        // bar itself publishes, on top of the device's own inset.
        .safeAreaPadding(.bottom)
        .padding(.bottom, DSTabBarView.preferredHeight())
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

private struct CoinageBalanceBreakdownView: View {
    let breakdown: CoinageBalanceBreakdownViewModel

    var onMakeAllVouchersReady: (() -> Void)?

    @State private var showDetails = false
    @State private var showExplanation = false

    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: .coinageSummaryTitle))
                .textStyle(.title16SemiBold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityId(AccessibilityID.Wallet.coinageHeader)

            totalHeadline

            CoinageCompositionBar(model: breakdown.composition)
                .padding(.vertical, 2)

            summaryLegend

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
                    Text(String(localized: showDetails ? .coinageHideDetails : .coinageShowDetails))
                        .textStyle(.body14SemiBold())
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.fgPrimary)
            }

            if showDetails {
                CoinageDetailsView(breakdown: breakdown)
                CoinageExplanationView(isExpanded: $showExplanation)
            }
        }
        .padding(16)
        .background(.bgSurfaceContainer, in: RoundedRectangle(cornerRadius: 24))
    }

    private var totalHeadline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: .coinageTotalBalance))
                .textStyle(.caption12Regular())
                .foregroundStyle(Color.fgSecondary)
                .accessibilityId(AccessibilityID.Wallet.coinageTotalBalanceLabel)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(breakdown.totalBalance)
                    .textStyle(.title32SemiBold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityId(AccessibilityID.Wallet.coinageTotalBalanceValue)

                Text(breakdown.symbol)
                    .textStyle(.caption12Regular())
                    .foregroundStyle(Color.fgSecondary)
            }
            .foregroundStyle(Color.fgPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three figures partition the total and are the three sections of the bar above, in the
    /// same order, each keyed to its section by a swatch.
    ///
    /// A grid rather than three stacked columns: a label long enough to wrap would otherwise push
    /// its own value down and leave the three figures on different lines.
    private var summaryLegend: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                ForEach(legendEntries) { entry in
                    HStack(spacing: 6) {
                        CoinageLegendSwatch(kind: entry.kind)

                        Text(entry.title)
                            .textStyle(.caption12Regular())
                            .foregroundStyle(Color.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityId(entry.labelAccessibilityId)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .gridCellAnchor(.topLeading)

            GridRow {
                ForEach(legendEntries) { entry in
                    Text(entry.value)
                        .textStyle(.body14SemiBold())
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityId(entry.valueAccessibilityId)
                }
            }
        }
    }

    private var legendEntries: [LegendEntry] {
        [
            LegendEntry(
                kind: .availableNow,
                title: String(localized: .coinageSpendable),
                value: breakdown.availableNowBalance,
                labelAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceLabel,
                valueAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceValue
            ),
            // No accessibility id yet: the registry lives in another repo.
            LegendEntry(
                kind: .gainingPrivacy,
                title: String(localized: .coinageLoading),
                value: breakdown.gainingPrivacyBalance
            ),
            LegendEntry(
                kind: .unavailable,
                title: String(localized: .coinageUnavailable),
                value: breakdown.pendingBalance,
                labelAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceLabel,
                valueAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceValue
            )
        ]
    }
}

/// One block per distinct depiction: the mark drawn once, then the values that share it.
///
/// Holdings arrive ordered, so anything that draws identically is already adjacent and the
/// grouping is a scan rather than a sort. Two holdings merge exactly when their status compares
/// equal, which is the same condition under which they would have drawn the same row twice.
private struct CoinageDetailsView: View {
    let breakdown: CoinageBalanceBreakdownViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.groups(of: breakdown.holdings)) { group in
                VStack(alignment: .leading, spacing: 3) {
                    switch group.status {
                    case let .coin(model):
                        CoinStatusView(model: model)
                    case let .voucher(model):
                        VoucherStatusView(model: model)
                    }

                    Text(verbatim: group.amounts)
                        .textStyle(.caption12Regular())
                        .foregroundStyle(.fgSecondary)
                }
            }
        }
    }
}

private extension CoinageDetailsView {
    struct Group: Identifiable {
        let id: String
        let status: CoinageHoldingViewModel.Status
        /// Values sharing this depiction, descending, repeats folded into a count.
        let amounts: String
    }

    static func groups(of holdings: [CoinageHoldingViewModel]) -> [Group] {
        var groups: [Group] = []
        var run: [CoinageHoldingViewModel] = []

        func flush() {
            guard let first = run.first else { return }
            groups.append(Group(id: first.id, status: first.status, amounts: amounts(of: run)))
            run = []
        }

        for holding in holdings {
            if holding.status != run.first?.status {
                flush()
            }
            run.append(holding)
        }
        flush()

        return groups
    }

    /// Counts consecutive repeats rather than tallying the whole run, so the values stay in the
    /// order the list put them in.
    static func amounts(of run: [CoinageHoldingViewModel]) -> String {
        var parts: [String] = []

        for holding in run {
            let amount = holding.amount ?? "—"

            if let last = parts.last, last == amount || last.hasPrefix("\(amount) ×") {
                let count = Int(last.split(separator: "×").last ?? "1") ?? 1
                parts[parts.count - 1] = "\(amount) ×\(count + 1)"
            } else {
                parts.append(amount)
            }
        }

        return parts.joined(separator: "   ")
    }
}

/// One of the three figures under the summary bar.
private struct LegendEntry: Identifiable {
    let kind: CoinageLegendSwatch.Kind
    let title: String
    let value: String
    var labelAccessibilityId: (any AccessibilityIdentifying)?
    var valueAccessibilityId: (any AccessibilityIdentifying)?

    var id: String { title }
}
