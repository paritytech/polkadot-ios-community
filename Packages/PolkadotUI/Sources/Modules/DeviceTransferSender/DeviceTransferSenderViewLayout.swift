import SwiftUI
import DesignSystem

/// The old phone's transfer screens; the Figma layout follows in its own step.
public struct DeviceTransferSenderViewLayout: View {
    @State public var viewModel = DeviceTransferSenderViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: DSSpacings.large) {
            DeviceTransferIllustration()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgSurfaceMain)
    }
}
