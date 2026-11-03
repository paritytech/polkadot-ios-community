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
                Picker(selection: $theme) {
                    ForEach(ThemeSelection.allCases, id: \.self) { theme in
                        Text(verbatim: theme.rawValue).tag(theme)
                    }
                } label: {
                    Text(verbatim: "Theme")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DSSpacings.mediumIncreased)
            }
            .environment(\.appTheme, theme)
            .preferredColorScheme(.dark)
    }
}
