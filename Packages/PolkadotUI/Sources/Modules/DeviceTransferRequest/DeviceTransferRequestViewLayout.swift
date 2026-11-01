import SwiftUI
import DesignSystem

/// The old phone's sheet for an incoming transfer request.
public struct DeviceTransferRequestViewLayout: View {
    @State public var viewModel = DeviceTransferRequestViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            BottomSheetBaseView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: DSSpacings.small) {
                        DeviceTransferIllustration()
                            .padding(.bottom, DSSpacings.small)
                        Text(String(localized: .deviceTransferRequestTitle))
                            .typography(.headlineSmall)
                            .foregroundStyle(Color.fgPrimary)
                        Text(String(localized: .deviceTransferRequestBody))
                            .typography(.paragraphLarge)
                            .foregroundStyle(Color.fgPrimary)
                    }
                    .padding(.horizontal, DSSpacings.small)
                    .padding(.vertical, DSSpacings.mediumIncreased)

                    if let newPhone = viewModel.newPhone {
                        DeviceTransferDeviceCard(
                            model: newPhone.model,
                            detail: String(localized: .deviceTransferDeviceNewPhone(
                                operatingSystem: newPhone.operatingSystem
                            )),
                            background: .bgSurfaceNested
                        )
                        .padding(.horizontal, DSSpacings.small)
                        .padding(.vertical, DSSpacings.small)
                    }

                    VStack(spacing: DSSpacings.mediumIncreased) {
                        DSButton(
                            String(localized: .deviceTransferRequestActionTransfer),
                            style: .primary,
                            expands: true,
                            action: { viewModel.onTransfer?() }
                        )
                        DSButton(
                            String(localized: .deviceTransferRequestActionDecline),
                            style: .tertiary,
                            expands: true,
                            action: { viewModel.onDecline?() }
                        )
                    }
                    .padding(.top, DSSpacings.mediumIncreased)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Incoming request") {
    let layout = DeviceTransferRequestViewLayout()
    layout.viewModel.newPhone = DeviceTransferPhone(model: "iPhone 17 Pro", operatingSystem: "iOS 26.1")
    return ThemeSwitchingPreview { layout }
}
