import SwiftUI
import PolkadotUI
import DesignSystem

struct RecipientLabelView: View {
    let avatar: AvatarViewModel
    let title: String

    var body: some View {
        HStack(spacing: DSSpacings.small) {
            Text(.recipientInputTo2)
                .typography(.paragraphLarge)
                .foregroundStyle(.fgSecondary)

            HStack(spacing: DSSpacings.tiny) {
                DSAvatar(viewModel: avatar, size: .s28)
                Text(title)
                    .typography(.bodyLarge)
                    .foregroundStyle(.fgPrimary)
            }
            .padding(.leading, DSSpacings.tiny)
            .padding(.trailing, DSSpacings.extraMedium)
            .padding(.vertical, DSSpacings.tiny)
            .background(.bgSurfaceContainer, in: Capsule())
            .overlay(Capsule().stroke(.strokePrimary, lineWidth: 1))
        }
    }
}
