import SwiftUI
import DesignSystem

/// "Lower quality → Higher quality": three mismatched coins become three identical ones. The Figma export
/// ships with a sub-caption under each label; those lines are masked out of the asset, as in the mock.
struct CoinQualityIllustration: View {
    var body: some View {
        Image(.coinQualityIllustration)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: DSRadii.large, style: .continuous))
            .accessibilityLabel(Text(.settingsPrivacymodeInfoQualityIllustration))
    }
}

#if DEBUG
    #Preview("CoinQualityIllustration") {
        CoinQualityIllustration()
            .padding()
            .background(Color.bgSurfaceContainer)
    }
#endif
