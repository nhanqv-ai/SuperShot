import Foundation
import CoreGraphics
import AppKit

// MARK: - Stitch Options

public struct StitchOptions: Sendable, Equatable {
    public var scrollbarStripWidth: CGFloat
    public var headerDedupHeight: CGFloat
    public var footerDedupHeight: CGFloat
    public var maxScrollHeightPx: CGFloat
    public var scaleFactor: CGFloat

    public init(
        scrollbarStripWidth: CGFloat = 24.0,
        headerDedupHeight: CGFloat = 80.0,
        footerDedupHeight: CGFloat = 80.0,
        maxScrollHeightPx: CGFloat = 15000.0,
        scaleFactor: CGFloat = 2.0
    ) {
        self.scrollbarStripWidth = max(0.0, min(scrollbarStripWidth, 100.0))
        self.headerDedupHeight = max(0.0, min(headerDedupHeight, 500.0))
        self.footerDedupHeight = max(0.0, min(footerDedupHeight, 500.0))
        self.maxScrollHeightPx = max(5000.0, min(maxScrollHeightPx, 30000.0))
        self.scaleFactor = max(1.0, scaleFactor)
    }
}

// MARK: - Stitch Result

public struct StitchResult: Sendable {
    public let image: CGImage
    public let totalHeight: CGFloat
    public let frameOffsets: [CGFloat]
    public let deduplicatedHeaderHeight: CGFloat
    public let deduplicatedFooterHeight: CGFloat
    public let isClampedToMaxHeight: Bool

    public init(
        image: CGImage,
        totalHeight: CGFloat,
        frameOffsets: [CGFloat],
        deduplicatedHeaderHeight: CGFloat = 0.0,
        deduplicatedFooterHeight: CGFloat = 0.0,
        isClampedToMaxHeight: Bool = false
    ) {
        self.image = image
        self.totalHeight = totalHeight
        self.frameOffsets = frameOffsets
        self.deduplicatedHeaderHeight = deduplicatedHeaderHeight
        self.deduplicatedFooterHeight = deduplicatedFooterHeight
        self.isClampedToMaxHeight = isClampedToMaxHeight
    }
}

// MARK: - Image Stitcher Errors

public enum ImageStitcherError: Error, LocalizedError, Sendable {
    case emptyFrames
    case invalidDimensions
    case contextAllocationFailed
    case imageGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .emptyFrames:
            return "Cannot stitch an empty list of frames."
        case .invalidDimensions:
            return "Frames have inconsistent or invalid dimensions."
        case .contextAllocationFailed:
            return "Failed to allocate CoreGraphics bitmap context."
        case .imageGenerationFailed:
            return "Failed to create final stitched CGImage."
        }
    }
}

// MARK: - Image Stitcher Engine

public final class ImageStitcher: Sendable {

    public struct OffsetEstimation: Sendable, Equatable {
        public let offset: Int
        public let isZeroDelta: Bool
        public let confidence: Double

        public init(offset: Int, isZeroDelta: Bool, confidence: Double) {
            self.offset = offset
            self.isZeroDelta = isZeroDelta
            self.confidence = confidence
        }
    }

    /// Primary batch stitching entry point conforming to PROJECT.md interface contract.
    public static func stitch(
        frames: [CGImage],
        options: StitchOptions = StitchOptions()
    ) throws -> StitchResult {
        guard let firstFrame = frames.first else {
            throw ImageStitcherError.emptyFrames
        }

        let width = firstFrame.width
        let height = firstFrame.height
        guard width > 0 && height > 0 else {
            throw ImageStitcherError.invalidDimensions
        }

        // Single frame edge case
        guard frames.count > 1 else {
            let h = CGFloat(height)
            return StitchResult(
                image: firstFrame,
                totalHeight: h,
                frameOffsets: [],
                deduplicatedHeaderHeight: 0,
                deduplicatedFooterHeight: 0,
                isClampedToMaxHeight: false
            )
        }

        // Validate dimension consistency with minor 1-2px rounding tolerance
        var normalizedFrames: [CGImage] = []
        normalizedFrames.reserveCapacity(frames.count)

        for frame in frames {
            if frame.width == width && frame.height == height {
                normalizedFrames.append(frame)
            } else if abs(frame.width - width) <= 2 && abs(frame.height - height) <= 2 {
                if let normalized = normalizeFrameDimensions(frame, targetWidth: width, targetHeight: height) {
                    normalizedFrames.append(normalized)
                } else {
                    throw ImageStitcherError.invalidDimensions
                }
            } else {
                throw ImageStitcherError.invalidDimensions
            }
        }
        let frames = normalizedFrames

        let scale = options.scaleFactor
        let scrollbarPx = Int(round(options.scrollbarStripWidth * scale))
        let effectiveWidth = max(1, width - scrollbarPx)
        let maxHeaderPx = min(height / 3, Int(round(options.headerDedupHeight * scale)))
        let maxFooterPx = min(height / 3, Int(round(options.footerDedupHeight * scale)))

        // 1. Detect Stationary Sticky Header & Footer on the first moving frame pair
        var movingPair: (CGImage, CGImage)? = nil
        for i in 0..<(frames.count - 1) {
            let est = estimateVerticalOffset(
                f1: frames[i],
                f2: frames[i + 1],
                effectiveWidth: effectiveWidth,
                headerH: 0,
                footerH: 0
            )
            if !est.isZeroDelta && est.offset > 0 {
                movingPair = (frames[i], frames[i + 1])
                break
            }
        }

        var detectedHeaderPx = 0
        var detectedFooterPx = 0
        if let (fA, fB) = movingPair {
            detectedHeaderPx = detectStationaryHeader(
                f1: fA,
                f2: fB,
                effectiveWidth: effectiveWidth,
                maxHeaderH: maxHeaderPx
            )
            detectedFooterPx = detectStationaryFooter(
                f1: fA,
                f2: fB,
                effectiveWidth: effectiveWidth,
                maxFooterH: maxFooterPx
            )
        }

        // 2. Calculate vertical offsets across all consecutive pairs
        var offsets: [Int] = []
        for i in 0..<(frames.count - 1) {
            let fA = frames[i]
            let fB = frames[i + 1]
            let est = estimateVerticalOffset(
                f1: fA,
                f2: fB,
                effectiveWidth: effectiveWidth,
                headerH: detectedHeaderPx,
                footerH: detectedFooterPx
            )
            offsets.append(est.offset)
        }

        // 3. Compute Total Target Height & Clamping
        let sumOffsets = offsets.reduce(0, +)
        if sumOffsets == 0 {
            return StitchResult(
                image: firstFrame,
                totalHeight: CGFloat(height),
                frameOffsets: [],
                deduplicatedHeaderHeight: 0,
                deduplicatedFooterHeight: 0,
                isClampedToMaxHeight: false
            )
        }

        let unconstrainedHeight = height + sumOffsets
        let maxAllowedPx = Int(round(options.maxScrollHeightPx))
        let isClamped = unconstrainedHeight > maxAllowedPx
        let finalHeight = min(unconstrainedHeight, maxAllowedPx)

        // 4. Allocate Destination CoreGraphics Context (Memory Safe Single Allocator)
        let colorSpace = firstFrame.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: finalHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageStitcherError.contextAllocationFailed
        }

        // 5. Direct Slice Blitting into Destination Context
        // In un-flipped CGContext, top-down coordinate y corresponds to rect y = finalHeight - (y + h)
        var yDestTopDown = 0

        // 5a. Top Sticky Header from Frame 0
        if detectedHeaderPx > 0 && yDestTopDown < finalHeight {
            let hSlice = min(detectedHeaderPx, finalHeight - yDestTopDown)
            if let slice = safeCrop(firstFrame, x: 0, y: 0, width: width, height: hSlice) {
                let destRect = CGRect(x: 0, y: finalHeight - (yDestTopDown + hSlice), width: width, height: hSlice)
                context.draw(slice, in: destRect)
                yDestTopDown += hSlice
            }
        }

        // 5b. Frame 0 Initial Content Slice [detectedHeaderPx ..< height - detectedFooterPx]
        let initialContentH = height - detectedHeaderPx - detectedFooterPx
        if initialContentH > 0 && yDestTopDown < finalHeight {
            let hSlice = min(initialContentH, finalHeight - yDestTopDown)
            if let slice = safeCrop(firstFrame, x: 0, y: detectedHeaderPx, width: width, height: hSlice) {
                let destRect = CGRect(x: 0, y: finalHeight - (yDestTopDown + hSlice), width: width, height: hSlice)
                context.draw(slice, in: destRect)
                yDestTopDown += hSlice
            }
        }

        // 5c. Newly revealed Slices from Frame 1 ..< N
        for (idx, offset) in offsets.enumerated() {
            guard yDestTopDown < finalHeight else { break }
            guard offset > 0 else { continue }

            let frame = frames[idx + 1]
            let srcY = height - detectedFooterPx - offset
            let hSlice = min(offset, finalHeight - yDestTopDown)
            guard srcY >= detectedHeaderPx, srcY + hSlice <= height else { continue }

            if let slice = safeCrop(frame, x: 0, y: srcY, width: width, height: hSlice) {
                let destRect = CGRect(x: 0, y: finalHeight - (yDestTopDown + hSlice), width: width, height: hSlice)
                context.draw(slice, in: destRect)
                yDestTopDown += hSlice
            }
        }

        // 5d. Bottom Sticky Footer from Final Frame
        if detectedFooterPx > 0 && yDestTopDown < finalHeight {
            let lastFrame = frames.last ?? firstFrame
            let hSlice = min(detectedFooterPx, finalHeight - yDestTopDown)
            let srcY = height - detectedFooterPx
            if let slice = safeCrop(lastFrame, x: 0, y: srcY, width: width, height: hSlice) {
                let destRect = CGRect(x: 0, y: finalHeight - (yDestTopDown + hSlice), width: width, height: hSlice)
                context.draw(slice, in: destRect)
                yDestTopDown += hSlice
            }
        }

        guard let finalImage = context.makeImage() else {
            throw ImageStitcherError.imageGenerationFailed
        }

        return StitchResult(
            image: finalImage,
            totalHeight: CGFloat(finalHeight),
            frameOffsets: offsets.map { CGFloat($0) },
            deduplicatedHeaderHeight: CGFloat(detectedHeaderPx),
            deduplicatedFooterHeight: CGFloat(detectedFooterPx),
            isClampedToMaxHeight: isClamped
        )
    }

    public static func safeCrop(
        _ image: CGImage,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let imgW = image.width
        let imgH = image.height
        guard x >= 0, y >= 0, x < imgW, y < imgH else { return nil }
        let safeW = min(width, imgW - x)
        let safeH = min(height, imgH - y)
        guard safeW > 0, safeH > 0 else { return nil }
        return image.cropping(to: CGRect(x: x, y: y, width: safeW, height: safeH))
    }

    /// Normalizes minor 1-2px frame rounding variances to match target canvas dimensions.
    private static func normalizeFrameDimensions(_ frame: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        if frame.width == targetWidth && frame.height == targetHeight {
            return frame
        }
        if frame.width >= targetWidth && frame.height >= targetHeight {
            return safeCrop(frame, x: 0, y: 0, width: targetWidth, height: targetHeight)
        }
        let colorSpace = frame.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage()
    }

    // MARK: - Stationary Row Boundary Detection

    public static func detectStationaryHeader(
        f1: CGImage,
        f2: CGImage,
        effectiveWidth: Int,
        maxHeaderH: Int,
        threshold: Double = 4.0
    ) -> Int {
        guard maxHeaderH > 0 else { return 0 }
        let h = min(maxHeaderH, f1.height)
        let sampleCols = min(32, effectiveWidth)

        let g1 = extractGrayscaleMatrix(image: f1, effectiveWidth: effectiveWidth, height: h, startY: 0, sampleCols: sampleCols)
        let g2 = extractGrayscaleMatrix(image: f2, effectiveWidth: effectiveWidth, height: h, startY: 0, sampleCols: sampleCols)

        var headerH = 0
        for r in 0..<h {
            var rowDiff: Int = 0
            let rowOffset = r * sampleCols
            for c in 0..<sampleCols {
                rowDiff += abs(Int(g1[rowOffset + c]) - Int(g2[rowOffset + c]))
            }
            let avg = Double(rowDiff) / Double(sampleCols)
            if avg <= threshold {
                headerH = r + 1
            } else {
                break
            }
        }

        guard headerH > 0 else { return 0 }

        // Variance & boundary edge check: ensure flat/solid regions are not treated as false-positive sticky headers
        var pixelSum: Double = 0
        let totalSamples = headerH * sampleCols
        for r in 0..<headerH {
            let rowOffset = r * sampleCols
            for c in 0..<sampleCols {
                pixelSum += Double(g1[rowOffset + c])
            }
        }
        let mean = pixelSum / Double(totalSamples)
        var varSum: Double = 0
        for r in 0..<headerH {
            let rowOffset = r * sampleCols
            for c in 0..<sampleCols {
                let diff = Double(g1[rowOffset + c]) - mean
                varSum += diff * diff
            }
        }
        let regionVariance = varSum / Double(totalSamples)
        if regionVariance >= 2.0 {
            return headerH
        }

        // If the candidate header is uniform, verify that f1 has a distinct contrast edge where the header ends
        if headerH < f1.height {
            let nextRowPixels = extractGrayscaleMatrix(image: f1, effectiveWidth: effectiveWidth, height: 1, startY: headerH, sampleCols: sampleCols)
            var nextRowSum: Double = 0
            for c in 0..<sampleCols {
                nextRowSum += Double(nextRowPixels[c])
            }
            let nextRowMean = nextRowSum / Double(sampleCols)
            if abs(nextRowMean - mean) >= 3.0 {
                return headerH
            }
        }

        return 0
    }

    public static func detectStationaryFooter(
        f1: CGImage,
        f2: CGImage,
        effectiveWidth: Int,
        maxFooterH: Int,
        threshold: Double = 4.0
    ) -> Int {
        guard maxFooterH > 0 else { return 0 }
        let h = min(maxFooterH, f1.height)
        let startY = f1.height - h
        let sampleCols = min(32, effectiveWidth)

        let g1 = extractGrayscaleMatrix(image: f1, effectiveWidth: effectiveWidth, height: h, startY: startY, sampleCols: sampleCols)
        let g2 = extractGrayscaleMatrix(image: f2, effectiveWidth: effectiveWidth, height: h, startY: startY, sampleCols: sampleCols)

        var footerH = 0
        for i in 0..<h {
            let r = h - 1 - i
            var rowDiff: Int = 0
            let rowOffset = r * sampleCols
            for c in 0..<sampleCols {
                rowDiff += abs(Int(g1[rowOffset + c]) - Int(g2[rowOffset + c]))
            }
            let avg = Double(rowDiff) / Double(sampleCols)
            if avg <= threshold {
                footerH = i + 1
            } else {
                break
            }
        }

        guard footerH > 0 else { return 0 }

        // Variance & boundary edge check: ensure flat/solid regions are not treated as false-positive sticky footers
        var pixelSum: Double = 0
        let totalSamples = footerH * sampleCols
        for i in 0..<footerH {
            let r = h - 1 - i
            let rowOffset = r * sampleCols
            for c in 0..<sampleCols {
                pixelSum += Double(g1[rowOffset + c])
            }
        }
        let mean = pixelSum / Double(totalSamples)
        var varSum: Double = 0
        for i in 0..<footerH {
            let r = h - 1 - i
            let rowOffset = r * sampleCols
            for c in 0..<sampleCols {
                let diff = Double(g1[rowOffset + c]) - mean
                varSum += diff * diff
            }
        }
        let regionVariance = varSum / Double(totalSamples)
        if regionVariance >= 2.0 {
            return footerH
        }

        // If candidate footer is uniform, verify that f1 has a distinct contrast edge immediately above the footer
        let boundaryRow = f1.height - footerH - 1
        if boundaryRow >= 0 {
            let prevRowPixels = extractGrayscaleMatrix(image: f1, effectiveWidth: effectiveWidth, height: 1, startY: boundaryRow, sampleCols: sampleCols)
            var prevRowSum: Double = 0
            for c in 0..<sampleCols {
                prevRowSum += Double(prevRowPixels[c])
            }
            let prevRowMean = prevRowSum / Double(sampleCols)
            if abs(prevRowMean - mean) >= 3.0 {
                return footerH
            }
        }

        return 0
    }

    // MARK: - Vertical Offset Estimation

    public static func estimateVerticalOffset(
        f1: CGImage,
        f2: CGImage,
        effectiveWidth: Int,
        headerH: Int = 0,
        footerH: Int = 0,
        minOffset: Int = 5,
        maxOffset: Int? = nil
    ) -> OffsetEstimation {
        let height = f1.height
        let maxOff = min(height - headerH - footerH - 1, maxOffset ?? (height - headerH - footerH - 10))
        guard maxOff >= minOffset else {
            return OffsetEstimation(offset: 0, isZeroDelta: true, confidence: 1.0)
        }

        let sampleCols = min(32, effectiveWidth)
        let g1 = extractGrayscaleMatrix(image: f1, effectiveWidth: effectiveWidth, height: height, startY: 0, sampleCols: sampleCols)
        let g2 = extractGrayscaleMatrix(image: f2, effectiveWidth: effectiveWidth, height: height, startY: 0, sampleCols: sampleCols)

        // Check for Zero-Delta (no displacement across content area)
        let checkRows = max(1, height - headerH - footerH)
        var zeroDiffSum: Int64 = 0
        for r in headerH..<(height - footerH) {
            let offset = r * sampleCols
            for c in 0..<sampleCols {
                zeroDiffSum += Int64(abs(Int(g1[offset + c]) - Int(g2[offset + c])))
            }
        }
        let avgZeroDiff = Double(zeroDiffSum) / Double(checkRows * sampleCols)
        if avgZeroDiff == 0 {
            return OffsetEstimation(offset: 0, isZeroDelta: true, confidence: 1.0)
        }

        var bestOffset = 0
        var bestScore = Double.greatestFiniteMagnitude
        var scores: [Double] = []

        for offset in minOffset...maxOff {
            let rowsToCompare = height - offset - footerH
            if rowsToCompare <= headerH { continue }

            var diffSum: Int64 = 0
            var count = 0
            for r2 in stride(from: headerH, to: rowsToCompare, by: 2) {
                let r1 = r2 + offset
                let o1 = r1 * sampleCols
                let o2 = r2 * sampleCols
                for c in stride(from: 0, to: sampleCols, by: 2) {
                    diffSum += Int64(abs(Int(g1[o1 + c]) - Int(g2[o2 + c])))
                    count += 1
                }
            }
            if count > 0 {
                let avg = Double(diffSum) / Double(count)
                scores.append(avg)
                if avg < bestScore {
                    bestScore = avg
                    bestOffset = offset
                }
            }
        }

        // Low-entropy flat-MAD offset bias guard:
        // If candidate offset scores have near-zero dynamic range / spread across the range
        // (e.g. solid white / uniform background with no features), offset estimation is degenerate.
        if scores.count > 1, let minS = scores.min(), let maxS = scores.max() {
            let scoreSpread = maxS - minS
            if scoreSpread < 0.5 && avgZeroDiff < 1.0 {
                return OffsetEstimation(offset: 0, isZeroDelta: true, confidence: 1.0)
            }
        }

        let isZero = (bestOffset == 0 || (avgZeroDiff <= bestScore && avgZeroDiff < 1.0))
        let finalOffset = isZero ? 0 : bestOffset
        let finalScore = isZero ? avgZeroDiff : bestScore
        return OffsetEstimation(
            offset: finalOffset,
            isZeroDelta: isZero,
            confidence: max(0.0, 1.0 - finalScore / 255.0)
        )
    }

    // MARK: - Row Luminance Extractor

    public static func extractRowLuminanceMeans(
        image: CGImage,
        effectiveWidth: Int,
        height: Int,
        startY: Int
    ) -> [Double] {
        var means = [Double](repeating: 0.0, count: height)
        let sampleCols = min(64, effectiveWidth)
        guard sampleCols > 0 && height > 0 else { return means }

        var grayPixels = [UInt8](repeating: 0, count: sampleCols * height)
        let grayColorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &grayPixels,
            width: sampleCols,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: sampleCols,
            space: grayColorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return means
        }

        if let sub = image.cropping(to: CGRect(x: 0, y: startY, width: effectiveWidth, height: height)) {
            ctx.draw(sub, in: CGRect(x: 0, y: 0, width: sampleCols, height: height))
            for r in 0..<height {
                var rowSum: Int64 = 0
                let rowOffset = r * sampleCols
                for c in 0..<sampleCols {
                    rowSum += Int64(grayPixels[rowOffset + c])
                }
                means[r] = Double(rowSum) / Double(sampleCols)
            }
        }

        return means
    }

    private static func extractGrayscaleMatrix(
        image: CGImage,
        effectiveWidth: Int,
        height: Int,
        startY: Int,
        sampleCols: Int
    ) -> [UInt8] {
        var grayPixels = [UInt8](repeating: 0, count: sampleCols * height)
        guard sampleCols > 0 && height > 0 else { return grayPixels }

        let grayColorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &grayPixels,
            width: sampleCols,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: sampleCols,
            space: grayColorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return grayPixels
        }

        if let sub = image.cropping(to: CGRect(x: 0, y: startY, width: effectiveWidth, height: height)) {
            ctx.draw(sub, in: CGRect(x: 0, y: 0, width: sampleCols, height: height))
        }

        return grayPixels
    }
}
