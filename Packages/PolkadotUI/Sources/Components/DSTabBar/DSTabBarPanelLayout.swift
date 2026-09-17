import UIKit

enum DSTabBarPanelLayout {
    static let columnsPerRow = 5
    static let iconSize: CGFloat = 36
    static let iconLabelGap: CGFloat = 4
    static let rowSpacing: CGFloat = 12
    static let verticalPadding: CGFloat = 16
    static let horizontalPadding: CGFloat = 4
    static let labelLineHeight: CGFloat = 16
    static let labelMaxLines = 2
    static var cornerRadius: CGFloat { DSTabBarMetrics.capsuleCornerRadius }

    static var labelHeight: CGFloat { labelLineHeight * CGFloat(labelMaxLines) }

    static func rowHeight(labelHeight: CGFloat) -> CGFloat {
        iconSize + iconLabelGap + labelHeight
    }

    static func contentHeight(rowHeights: [CGFloat]) -> CGFloat {
        guard !rowHeights.isEmpty else {
            return 0
        }
        return rowHeights.reduce(0, +)
            + CGFloat(rowHeights.count - 1) * rowSpacing
            + verticalPadding * 2
    }

    /// The container stacks the panel above the capsule unless the capsule is hidden, so it must fit
    /// the content plus the capsule height unless reservesCapsule is false.
    static func panelHeight(contentHeight: CGFloat, availableHeight: CGFloat, reservesCapsule: Bool = true)
        -> CGFloat {
        let capsuleReservation = reservesCapsule ? DSTabBarMetrics.capsuleHeight : 0
        return min(contentHeight + capsuleReservation, max(0, availableHeight))
    }

    static func panelHeight(rowHeights: [CGFloat], availableHeight: CGFloat) -> CGFloat {
        panelHeight(contentHeight: contentHeight(rowHeights: rowHeights), availableHeight: availableHeight)
    }
}
