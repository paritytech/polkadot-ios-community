import UIKit

public enum DSTabBarCentreSlot {
    public enum Half: Equatable {
        case qr
        case tabs
    }

    static let slotInset: CGFloat = 6
    static let dividerWidth: CGFloat = 1
    static let dividerVerticalInset: CGFloat = 14

    static func slotFrame(itemFrame: CGRect) -> CGRect {
        itemFrame.insetBy(dx: slotInset, dy: 0)
    }

    static func halfFrame(_ half: Half, inSlot slot: CGRect) -> CGRect {
        CGRect(
            x: half == .qr ? slot.minX : slot.midX,
            y: slot.minY,
            width: slot.width / 2,
            height: slot.height
        )
    }

    static func iconFrame(_ half: Half, inSlot slot: CGRect) -> CGRect {
        let icon = DSTabBarMetrics.iconSize
        return CGRect(
            x: (halfFrame(half, inSlot: slot).midX - icon / 2).rounded(),
            y: (slot.minY + (slot.height - icon) / 2).rounded(),
            width: icon,
            height: icon
        )
    }

    static func half(atX xPosition: CGFloat, inSlot slot: CGRect) -> Half {
        xPosition < slot.midX ? .qr : .tabs
    }

    static func isTabsActive(isPanelOpen: Bool, isSPAMounted: Bool) -> Bool {
        isPanelOpen || isSPAMounted
    }

    static func isQRActive(isQRSelected: Bool, isPanelOpen: Bool, isSPAMounted: Bool) -> Bool {
        isQRSelected && !isTabsActive(isPanelOpen: isPanelOpen, isSPAMounted: isSPAMounted)
    }
}
