import SwiftUI
import DesignSystem

/// Wraps a preview with a picker that switches between the design system themes.
struct ThemeSwitchingPreview<Content: View>: View {
    let content: Content
    @State private var theme: ThemeSelection = .berlinNight

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top) {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeSelection.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DSSpacings.mediumIncreased)
            }
            .environment(\.appTheme, theme)
            .preferredColorScheme(.dark)
    }
}
