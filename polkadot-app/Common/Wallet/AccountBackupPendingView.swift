import SwiftUI
import PolkadotUI
import DesignSystem

/// Shown while this installation's on-chain registration has not landed in the expected time: until
/// it does, balance allocated here could not be recovered from the seed alone.
struct AccountBackupPendingView: View {
    var body: some View {
        WalletCardContainer(
            color: Color.bgSurfaceContainer,
            contentPadding: 16
        ) {
            Label {
                Text(.BalanceSync.accountBackupPending)
                    .typography(.bodyMedium)
                    .foregroundStyle(.fgPrimary)
            } icon: {
                Image(.iconInfo20)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.fgWarning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
