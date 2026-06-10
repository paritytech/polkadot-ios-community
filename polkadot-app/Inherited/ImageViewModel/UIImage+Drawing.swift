import UIKit

extension UIImage {
    static func background(
        from color: UIColor,
        size: CGSize = CGSize(width: 1.0, height: 1.0),
        cornerRadius: CGFloat = 0.0,
        contentScale: CGFloat = 1.0
    ) -> UIImage? {
        let rect = CGRect(origin: .zero, size: size)
        let bezierPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)

        UIGraphicsBeginImageContextWithOptions(size, false, contentScale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        context.setFillColor(color.cgColor)
        context.addPath(bezierPath.cgPath)
        context.fillPath()

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }

    func crop(targetSize: CGSize, cornerRadius: CGFloat, contentScale: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        guard targetSize.width > 0, targetSize.height > 0 else {
            return nil
        }

        var drawingSize = CGSize(width: targetSize.width, height: targetSize.width * size.height / size.width)

        if drawingSize.height < targetSize.height {
            drawingSize.height = targetSize.height
            drawingSize.width = targetSize.height * size.width / size.height
        }

        UIGraphicsBeginImageContextWithOptions(targetSize, false, contentScale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        let contextRect = CGRect(origin: .zero, size: targetSize)

        let drawingOrigin = CGPoint(
            x: contextRect.midX - drawingSize.width / 2.0,
            y: contextRect.midY - drawingSize.height / 2.0
        )
        let drawingRect = CGRect(origin: drawingOrigin, size: drawingSize)

        let scaledCornerRadius = cornerRadius
        let bezierPath = UIBezierPath(roundedRect: contextRect, cornerRadius: scaledCornerRadius)
        context.addPath(bezierPath.cgPath)
        context.clip()

        draw(in: drawingRect)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }

    func tinted(with color: UIColor, opaque: Bool = false) -> UIImage? {
        let templateImage = withRenderingMode(.alwaysTemplate)

        UIGraphicsBeginImageContextWithOptions(size, opaque, scale)

        color.set()
        templateImage.draw(in: CGRect(origin: .zero, size: size))

        let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return tintedImage
    }

    func withAttentionBadge(
        badgeColor: UIColor,
        badgeRadius: CGFloat,
        badgeOffset: CGPoint
    ) -> UIImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let badgeCenterX = size.width - badgeOffset.x
        let badgeCenterY = badgeOffset.y

        let rightExtension = max(0, (badgeCenterX + badgeRadius) - size.width)
        let leftExtension = max(0, badgeRadius - badgeCenterX)
        let topExtension = max(0, badgeRadius - badgeCenterY)
        let bottomExtension = max(0, (badgeCenterY + badgeRadius) - size.height)

        let horizontalPadding = max(leftExtension, rightExtension)
        let verticalPadding = max(topExtension, bottomExtension)

        let newSize = CGSize(
            width: size.width + horizontalPadding * 2,
            height: size.height + verticalPadding * 2
        )

        let imageOrigin = CGPoint(x: horizontalPadding, y: verticalPadding)

        let badgeCenterInNewCanvas = CGPoint(
            x: imageOrigin.x + badgeCenterX,
            y: imageOrigin.y + badgeCenterY
        )

        let diameter = badgeRadius * 2
        let badgeRect = CGRect(
            x: badgeCenterInNewCanvas.x - badgeRadius,
            y: badgeCenterInNewCanvas.y - badgeRadius,
            width: diameter,
            height: diameter
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let image = renderer.image { context in
            draw(in: CGRect(origin: imageOrigin, size: size))

            let cgContext = context.cgContext
            cgContext.setFillColor(badgeColor.cgColor)
            cgContext.fillEllipse(in: badgeRect)
        }

        return image.withRenderingMode(renderingMode)
    }
}
