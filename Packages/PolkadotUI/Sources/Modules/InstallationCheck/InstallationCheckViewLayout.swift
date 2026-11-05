import SwiftUI
import DesignSystem

/// Shown while this phone's active installation status is read for the first time.
public struct InstallationCheckViewLayout: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(String(localized: .deviceTransferCheckTitle))
                .typography(.titleLarge)
                .foregroundStyle(Color.fgPrimary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .background(Color.bgSurfaceMain)
    }
}

#Preview {
    InstallationCheckViewLayout()
}
