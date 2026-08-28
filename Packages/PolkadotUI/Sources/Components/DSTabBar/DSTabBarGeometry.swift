import UIKit

enum DSTabBarMetrics {
    static let capsuleHeight: CGFloat = 62
    static let itemHeight: CGFloat = 54
    static let innerInset: CGFloat = 4
    static let rowPadding: CGFloat = 2
    static let itemOverlap: CGFloat = 8
    static let horizontalMargin: CGFloat = 21
    static let bottomGap: CGFloat = 21
    static let maxWidth: CGFloat = 500
    static let iconSize: CGFloat = 28
    static let itemTopPadding: CGFloat = 6
    static let itemBottomPadding: CGFloat = 7
    static let pillLeftExtension: CGFloat = 2
    static let pillRightExtension: CGFloat = 2.4
    static let badgeDiameter: CGFloat = 8
    static let liftedScaleX: CGFloat = 1.08
    static let liftedScaleY: CGFloat = 1.3
    static let foldedVisibleWidth: CGFloat = 19
    static let foldFlickVelocity: CGFloat = 800
    static let foldFlickMinTravel: CGFloat = 20
    static let foldGrabZoneWidth: CGFloat = 44
    static let foldSettleFraction: CGFloat = 0.3
    static let foldTapSlop: CGFloat = 10
    static let foldFlickMaxSampleAge: TimeInterval = 0.05
    static let selectionCancelVerticalSlop: CGFloat = 44
    static let selectionSpringDuration: TimeInterval = 0.4
    static let selectionSpringDamping: CGFloat = 0.8

    static var capsuleCornerRadius: CGFloat { capsuleHeight / 2 }
    static var pillCornerRadius: CGFloat { itemHeight / 2 }
}

enum DSTabBarGeometry {
    static func capsuleWidth(availableWidth: CGFloat) -> CGFloat {
        let inset = availableWidth - DSTabBarMetrics.horizontalMargin * 2
        return max(0, min(inset, DSTabBarMetrics.maxWidth))
    }

    static func capsuleFrame(availableWidth: CGFloat) -> CGRect {
        let width = capsuleWidth(availableWidth: availableWidth)
        return CGRect(
            x: ((availableWidth - width) / 2).rounded(),
            y: 0,
            width: width,
            height: DSTabBarMetrics.capsuleHeight
        )
    }

    static func foldedTranslationX(availableWidth: CGFloat) -> CGFloat {
        DSTabBarMetrics.foldedVisibleWidth - capsuleFrame(availableWidth: availableWidth).maxX
    }

    static func hiddenTranslationX(availableWidth: CGFloat) -> CGFloat {
        -capsuleFrame(availableWidth: availableWidth).maxX
    }

    static func rowWidth(capsuleWidth: CGFloat) -> CGFloat {
        max(0, capsuleWidth - DSTabBarMetrics.innerInset * 2)
    }

    static func clampedPillOriginX(_ xPosition: CGFloat, pillWidth: CGFloat, rowWidth: CGFloat) -> CGFloat {
        max(0, min(xPosition, rowWidth - pillWidth))
    }
}

struct DSTabBarRow {
    let width: CGFloat
    let itemCount: Int
    let isCentreExpanded: Bool
    let hasTrailingSlot: Bool
}

extension DSTabBarRow {
    var centreIndex: Int? {
        itemCount == 0 ? nil : itemCount / 2
    }

    var trailingSlotFrame: CGRect? {
        guard hasTrailingSlot else {
            return nil
        }
        return unitFrame(atUnitIndex: unitCount - 1, span: 1)
    }

    var draggableWidth: CGFloat {
        trailingSlotFrame?.minX ?? width
    }

    func itemFrame(at index: Int) -> CGRect {
        unitFrame(atUnitIndex: unitIndex(forItemAt: index), span: unitSpan(forItemAt: index))
    }

    func pillFrame(at index: Int) -> CGRect {
        let item = itemFrame(at: index)
        return CGRect(
            x: item.minX - DSTabBarMetrics.pillLeftExtension,
            y: item.minY,
            width: item.width + DSTabBarMetrics.pillLeftExtension + DSTabBarMetrics.pillRightExtension,
            height: item.height
        )
    }

    func nearestItemIndex(toX xPosition: CGFloat) -> Int {
        guard itemCount > 0 else {
            return 0
        }
        let centres = (0 ..< itemCount).map { itemFrame(at: $0).midX }
        let nearestIndex = centres.indices.min {
            abs(centres[$0] - xPosition) < abs(centres[$1] - xPosition)
        }
        return nearestIndex ?? 0
    }
}

private extension DSTabBarRow {
    var unitCount: Int {
        itemCount + (isCentreExpanded ? 1 : 0) + (hasTrailingSlot ? 1 : 0)
    }

    var unitWidth: CGFloat {
        guard unitCount > 0 else {
            return 0
        }
        let usable = width - DSTabBarMetrics.rowPadding * 2
        let overlapTotal = CGFloat(unitCount - 1) * DSTabBarMetrics.itemOverlap
        return max(0, (usable + overlapTotal) / CGFloat(unitCount))
    }

    var unitStride: CGFloat {
        unitWidth - DSTabBarMetrics.itemOverlap
    }

    func unitSpan(forItemAt index: Int) -> Int {
        isCentreExpanded && index == centreIndex ? 2 : 1
    }

    func unitIndex(forItemAt index: Int) -> Int {
        guard isCentreExpanded, let centreIndex, index > centreIndex else {
            return index
        }
        return index + 1
    }

    func unitFrame(atUnitIndex unitIndex: Int, span: Int) -> CGRect {
        CGRect(
            x: DSTabBarMetrics.rowPadding + CGFloat(unitIndex) * unitStride,
            y: 0,
            width: unitWidth + CGFloat(span - 1) * unitStride,
            height: DSTabBarMetrics.itemHeight
        )
    }
}
