import Foundation
import CoreGraphics
import AppKit
import CoreText
import CoreImage

/// High-fidelity rasterization engine compositing vector annotations and blur filters onto bitmaps.
public struct ImageRenderer {

    /// Rasterizes an array of vector annotations directly onto a base CGImage.
    /// - Parameters:
    ///   - baseImage: The background screenshot bitmap.
    ///   - annotations: Vector objects to composite.
    ///   - cropRect: Optional crop subregion in base image points.
    ///   - scale: Backing scale factor (default 2.0 for Retina).
    /// - Returns: Pristine composited CGImage or nil if rasterization fails.
    public static func render(
        baseImage: CGImage,
        annotations: [AnnotationObject],
        cropRect: CGRect? = nil,
        scale: CGFloat = 2.0
    ) -> CGImage? {
        let baseW = CGFloat(baseImage.width)
        let baseH = CGFloat(baseImage.height)

        let rawTarget = cropRect ?? CGRect(x: 0, y: 0, width: baseW / scale, height: baseH / scale)
        let targetRect = rawTarget.standardized
        guard targetRect.width > 0 && targetRect.height > 0 && !targetRect.isNull else {
            return nil
        }
        let pixelW = max(1, Int(round(targetRect.width * scale)))
        let pixelH = max(1, Int(round(targetRect.height * scale)))

        let colorSpace = baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: pixelW * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        // Flip coordinates so (0,0) is top-left in point space
        let effectiveHeightPt = CGFloat(pixelH) / scale
        let baseWidthPt = baseW / scale
        let baseHeightPt = baseH / scale
        context.translateBy(x: 0, y: CGFloat(pixelH))
        context.scaleBy(x: scale, y: -scale)

        // Draw cropped base image aligned with top-left targetRect origin
        let drawOriginX = -targetRect.minX
        let drawOriginY = -targetRect.minY

        context.saveGState()
        context.translateBy(x: 0, y: effectiveHeightPt)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(
            baseImage,
            in: CGRect(
                x: drawOriginX,
                y: effectiveHeightPt - drawOriginY - baseHeightPt,
                width: baseWidthPt,
                height: baseHeightPt
            )
        )
        context.restoreGState()

        // 1. First pass: Composite Region Blur / Pixelate overlays
        for obj in annotations where obj.tool == .blur {
            drawBlurRegion(
                obj: obj,
                baseImage: baseImage,
                context: context,
                targetRect: targetRect,
                effectiveHeightPt: effectiveHeightPt,
                scale: scale
            )
        }

        // 2. Second pass: Composite Vector Drawing Annotations (translated by targetRect origin)
        context.saveGState()
        context.translateBy(x: -targetRect.minX, y: -targetRect.minY)
        for obj in annotations where obj.tool != .blur {
            drawVectorAnnotation(obj: obj, context: context)
        }
        context.restoreGState()

        return context.makeImage()
    }

    // MARK: - Vector Object Drawing

    private static func drawVectorAnnotation(obj: AnnotationObject, context: CGContext) {
        let nsColor = ColorPreset(name: "", hex: obj.colorHex).toNSColor()
        context.saveGState()

        switch obj.tool {
        case .rectangle:
            context.setStrokeColor(nsColor.cgColor)
            context.setLineWidth(obj.strokeWidth)
            context.setLineJoin(.round)
            context.stroke(obj.bounds)

        case .ellipse:
            context.setStrokeColor(nsColor.cgColor)
            context.setLineWidth(obj.strokeWidth)
            context.strokeEllipse(in: obj.bounds)

        case .line:
            guard obj.points.count >= 2 else { break }
            context.setStrokeColor(nsColor.cgColor)
            context.setLineWidth(obj.strokeWidth)
            context.setLineCap(.round)
            context.strokeLineSegments(between: [obj.points[0], obj.points[1]])

        case .arrow:
            guard obj.points.count >= 2 else { break }
            drawArrow(p1: obj.points[0], p2: obj.points[1], strokeWidth: obj.strokeWidth, color: nsColor, context: context)

        case .pen:
            guard !obj.points.isEmpty else { break }
            context.setStrokeColor(nsColor.cgColor)
            context.setLineWidth(obj.strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let path = buildSmoothSplinePath(points: obj.points)
            context.addPath(path)
            context.strokePath()

        case .highlighter:
            guard !obj.points.isEmpty else { break }
            context.setBlendMode(.multiply)
            let markerColor = nsColor.withAlphaComponent(0.35)
            context.setStrokeColor(markerColor.cgColor)
            context.setLineWidth(max(16.0, obj.strokeWidth))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let path = buildSmoothSplinePath(points: obj.points)
            context.addPath(path)
            context.strokePath()

        case .text:
            drawTypography(obj: obj, context: context)

        case .blur, .select:
            break
        }

        context.restoreGState()
    }

    // MARK: - Arrow Trigonometry & Geometry

    private static func drawArrow(p1: CGPoint, p2: CGPoint, strokeWidth: CGFloat, color: NSColor, context: CGContext) {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let len = hypot(dx, dy)
        guard len > 1.0 else { return }

        let theta = atan2(dy, dx)
        let headLen = max(12.0, min(len * 0.5, strokeWidth * 4.0))
        let wingAngle: CGFloat = 0.488 // ~28 degrees

        let shaftEnd = CGPoint(
            x: p2.x - (headLen * 0.7) * cos(theta),
            y: p2.y - (headLen * 0.7) * sin(theta)
        )

        let w1 = CGPoint(
            x: p2.x - headLen * cos(theta - wingAngle),
            y: p2.y - headLen * sin(theta - wingAngle)
        )
        let w2 = CGPoint(
            x: p2.x - headLen * cos(theta + wingAngle),
            y: p2.y - headLen * sin(theta + wingAngle)
        )

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.strokeLineSegments(between: [p1, shaftEnd])

        let arrowPath = CGMutablePath()
        arrowPath.move(to: p2)
        arrowPath.addLine(to: w1)
        arrowPath.addLine(to: w2)
        arrowPath.closeSubpath()

        context.setFillColor(color.cgColor)
        context.addPath(arrowPath)
        context.fillPath()
    }

    // MARK: - Smooth Spline Path

    private static func buildSmoothSplinePath(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)

        if points.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2))
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for i in 1..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let mid = CGPoint(x: (p0.x + p1.x) / 2.0, y: (p0.y + p1.y) / 2.0)
            path.addQuadCurve(to: mid, control: p0)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    // MARK: - Typography Rendering

    private static func drawTypography(obj: AnnotationObject, context: CGContext) {
        guard !obj.text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: obj.fontSize, weight: .semibold)
        let nsColor = ColorPreset(name: "", hex: obj.colorHex).toNSColor()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor
        ]

        let lines = obj.text.components(separatedBy: .newlines)
        let lineHeight = obj.fontSize * 1.25

        for (index, rawLine) in lines.enumerated() {
            guard !rawLine.isEmpty else { continue }
            let attrString = NSAttributedString(string: rawLine, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)

            context.saveGState()
            context.translateBy(x: obj.bounds.minX, y: obj.bounds.minY + obj.fontSize + CGFloat(index) * lineHeight)
            context.scaleBy(x: 1.0, y: -1.0)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    // MARK: - Region Blur / Software Pixelation

    private static func drawBlurRegion(
        obj: AnnotationObject,
        baseImage: CGImage,
        context: CGContext,
        targetRect: CGRect,
        effectiveHeightPt: CGFloat,
        scale: CGFloat
    ) {
        let b = obj.bounds
        let intersect = b.intersection(targetRect)
        guard !intersect.isNull && intersect.width > 0 && intersect.height > 0 else { return }

        let localX = intersect.minX - targetRect.minX
        let localY = intersect.minY - targetRect.minY

        if let ciFiltered = renderCoreImagePixelate(baseImage: baseImage, rect: intersect, scale: scale) {
            context.saveGState()
            context.translateBy(x: 0, y: effectiveHeightPt)
            context.scaleBy(x: 1.0, y: -1.0)
            let drawY = -(localY + intersect.height) + effectiveHeightPt
            context.draw(ciFiltered, in: CGRect(x: localX, y: drawY, width: intersect.width, height: intersect.height))
            context.restoreGState()
            return
        }

        drawSoftwarePixelation(rect: CGRect(x: localX, y: localY, width: intersect.width, height: intersect.height), context: context)
    }

    private static func renderCoreImagePixelate(baseImage: CGImage, rect: CGRect, scale: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: baseImage)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(12.0 * scale, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return nil }

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let rawCrop = CGRect(
            x: rect.minX * scale,
            y: (CGFloat(baseImage.height) - (rect.minY + rect.height) * scale),
            width: rect.width * scale,
            height: rect.height * scale
        )
        let crop = rawCrop.intersection(ciImage.extent)
        guard !crop.isNull, crop.width >= 1, crop.height >= 1 else { return nil }

        return ciContext.createCGImage(output, from: crop)
    }

    private static func drawSoftwarePixelation(rect: CGRect, context: CGContext) {
        context.saveGState()
        let blockSize: CGFloat = 12.0
        let cols = max(1, Int(ceil(rect.width / blockSize)))
        let rows = max(1, Int(ceil(rect.height / blockSize)))

        for r in 0..<rows {
            for c in 0..<cols {
                let cellX = rect.minX + CGFloat(c) * blockSize
                let cellY = rect.minY + CGFloat(r) * blockSize
                let cellW = min(blockSize, rect.maxX - cellX)
                let cellH = min(blockSize, rect.maxY - cellY)
                let cellRect = CGRect(x: cellX, y: cellY, width: cellW, height: cellH)

                let shade = ((r + c) % 2 == 0) ? 0.45 : 0.55
                context.setFillColor(gray: shade, alpha: 0.90)
                context.fill(cellRect)
            }
        }
        context.restoreGState()
    }
}
