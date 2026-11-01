import SwiftUI
import DesignSystem

public struct DeviceTransferPhone: Equatable {
    public let model: String
    public let operatingSystem: String

    public init(model: String, operatingSystem: String) {
        self.model = model
        self.operatingSystem = operatingSystem
    }
}

/// Figma "DT/Transfer illustration": the old phone, arrows, the new phone.
public struct DeviceTransferIllustration: View {
    public init() {}

    public var body: some View {
        HStack(spacing: DSSpacings.mediumIncreased) {
            DeviceTransferPhoneGlyph(width: 56, height: 100, lineWidth: 3)
                .opacity(0.4)
            HStack(spacing: -12) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Image(.iconChevronRight)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color.fgPrimary.opacity(0.4 + 0.3 * Double(index)))
                }
            }
            DeviceTransferPhoneGlyph(width: 56, height: 100, lineWidth: 3)
        }
        .accessibilityHidden(true)
    }
}

/// Figma "DT/Phone glyph": a phone outline with its island.
public struct DeviceTransferPhoneGlyph: View {
    let width: CGFloat
    let height: CGFloat
    let lineWidth: CGFloat

    public init(width: CGFloat, height: CGFloat, lineWidth: CGFloat) {
        self.width = width
        self.height = height
        self.lineWidth = lineWidth
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: width / 4)
            .strokeBorder(Color.fgPrimary, lineWidth: lineWidth)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.fgPrimary)
                    .frame(width: width * 0.32, height: height * 0.05)
                    .padding(.top, height * 0.09)
            }
            .frame(width: width, height: height)
    }
}

/// Figma "DT/Device card". Inside a sheet it sits one surface level up.
public struct DeviceTransferDeviceCard: View {
    let model: String
    let detail: String
    let background: Color

    public init(model: String, detail: String, background: Color = .bgSurfaceContainer) {
        self.model = model
        self.detail = detail
        self.background = background
    }

    public var body: some View {
        HStack(spacing: DSSpacings.mediumIncreased) {
            DeviceTransferPhoneGlyph(width: 22.4, height: 40, lineWidth: 1.2)
                .frame(width: 44, height: 44)
                .background(Color.bgSurfaceNested, in: Circle())
            VStack(alignment: .leading, spacing: DSSpacings.extraTiny) {
                Text(model)
                    .typography(.bodyMediumEmphasized)
                    .foregroundStyle(Color.fgPrimary)
                Text(detail)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.fgSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(DSSpacings.mediumIncreased)
        .background(background, in: RoundedRectangle(cornerRadius: DSSpacings.large))
    }
}

/// Figma "Waiting": a spinner and what the phone waits for.
public struct DeviceTransferWaitingRow: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: DSSpacings.small) {
            LoadingSpinner(lineWidth: 2, strokeStyle: .fgSecondary)
                .frame(width: 20, height: 20)
            Text(text)
                .typography(.bodyMedium)
                .foregroundStyle(Color.fgSecondary)
        }
    }
}

/// Figma "Done row": a finished step.
public struct DeviceTransferDoneRow: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: DSSpacings.small) {
            Image(.icon20CheckCircle)
                .foregroundStyle(Color.fgSuccess)
            Text(text)
                .typography(.bodyMedium)
                .foregroundStyle(Color.fgPrimary)
            Spacer(minLength: 0)
        }
    }
}

/// Figma "DT/Progress": label and percent, the bar, and a detail line.
public struct DeviceTransferProgressBar: View {
    let label: String?
    let fraction: Double
    let detail: String?

    public init(label: String?, fraction: Double, detail: String?) {
        self.label = label
        self.fraction = fraction
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacings.extraMedium) {
            HStack {
                if let label {
                    Text(label).foregroundStyle(Color.fgPrimary)
                }
                Spacer(minLength: 0)
                Text(String(localized: .deviceTransferProgressPercent(percent: percent)))
                    .foregroundStyle(Color.fgSecondary)
            }
            .typography(.bodyMediumEmphasized)

            GeometryReader { proxy in
                Capsule()
                    .fill(Color.bgActionPrimary)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
            .frame(height: 8)
            .background(Color.bgSurfaceContainer, in: Capsule())

            if let detail {
                Text(detail)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.fgSecondary)
            }
        }
    }

    var percent: Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }
}

/// Figma "Bottom sheet base" for transfer confirmations: a warning, what follows, and a destructive confirm.
struct DeviceTransferConfirmationSheet: View {
    let content: DeviceTransferConfirmationContent
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        BottomSheetBaseView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: DSSpacings.small) {
                    Image(.iconAlertCircle)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .foregroundStyle(Color.fgWarning)
                        .padding(.bottom, DSSpacings.small)
                    Text(content.title)
                        .typography(.headlineSmall)
                        .foregroundStyle(Color.fgPrimary)
                    Text(content.message)
                        .typography(.paragraphLarge)
                        .foregroundStyle(Color.fgPrimary)
                }
                .padding(.horizontal, DSSpacings.small)
                .padding(.vertical, DSSpacings.mediumIncreased)

                if !content.points.isEmpty {
                    VStack(alignment: .leading, spacing: DSSpacings.extraMedium) {
                        ForEach(content.points, id: \.self) { point in
                            bullet(point)
                        }
                    }
                    .padding(.horizontal, DSSpacings.small)
                    .padding(.vertical, DSSpacings.small)
                }

                VStack(spacing: DSSpacings.mediumIncreased) {
                    DSButton(content.confirmTitle, style: .destructive, expands: true, action: onConfirm)
                    DSButton(content.dismissTitle, style: .tertiary, expands: true, action: onDismiss)
                }
                .padding(.top, DSSpacings.mediumIncreased)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacings.extraMedium) {
            Circle()
                .fill(Color.fgSecondary)
                .frame(width: 6, height: 6)
            Text(text)
                .typography(.bodyMedium)
                .foregroundStyle(Color.fgSecondary)
            Spacer(minLength: 0)
        }
    }
}

struct DeviceTransferConfirmationContent {
    let title: String
    let message: String
    let points: [String]
    let confirmTitle: String
    let dismissTitle: String
}
