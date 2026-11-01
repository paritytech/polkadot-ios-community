import SwiftUI
import DesignSystem

struct DeviceTransferAction {
    let title: String
    let style: DSButtonStyle.Style
    let handler: () -> Void

    init(_ title: LocalizedStringResource, _ style: DSButtonStyle.Style, handler: @escaping () -> Void) {
        self.title = String(localized: title)
        self.style = style
        self.handler = handler
    }
}

/// Every transfer screen in Figma: a header, centred texts, details, and the buttons pinned to the bottom.
struct DeviceTransferScreen<Header: View, Details: View>: View {
    let title: String
    let message: String?
    let actions: [DeviceTransferAction]
    @ViewBuilder let header: () -> Header
    @ViewBuilder let details: () -> Details

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DSSpacings.large) {
                header()
                texts
                details()
            }
            .padding(.horizontal, DSSpacings.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: DSSpacings.small) {
                ForEach(actions, id: \.title) { action in
                    DSButton(
                        action.title,
                        style: action.style,
                        size: .largeIncreased,
                        expands: true,
                        action: action.handler
                    )
                }
            }
            .padding(.horizontal, DSSpacings.mediumIncreased)
            .padding(.top, DSSpacings.small)
        }
        .padding(.bottom, DSSpacings.mediumIncreased)
        .background(Color.bgSurfaceMain)
    }

    private var texts: some View {
        VStack(spacing: DSSpacings.large) {
            Text(title)
                .typography(.headlineMedium)
                .foregroundStyle(Color.fgPrimary)
            if let message {
                Text(message)
                    .typography(.paragraphLarge)
                    .foregroundStyle(Color.fgSecondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// Figma "56/…" status icons that replace the illustration.
struct DeviceTransferStatusIcon: View {
    let resource: ImageResource
    let color: Color

    var body: some View {
        Image(resource)
            .resizable()
            .frame(width: 56, height: 56)
            .foregroundStyle(color)
    }
}

enum DeviceTransferText {
    static func paused(at progress: Double) -> String {
        String(localized: .deviceTransferProgressPaused(percent: Int((progress * 100).rounded())))
    }
}
