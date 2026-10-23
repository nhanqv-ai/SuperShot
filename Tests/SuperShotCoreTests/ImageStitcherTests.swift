import Foundation
import CoreGraphics
import AppKit

#if canImport(SuperShotCore)
import SuperShotCore
#endif

// MARK: - Synthetic Frame Generator for Deterministic Headless Testing

public struct SyntheticFrameGenerator {
    public static func createMasterCanvas(
        width: Int = 400,
        totalHeight: Int = 1200,
        headerHeight: Int = 60,
        footerHeight: Int = 40
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        for y in 0..<totalHeight {
            for x in 0..<width {
                let r = CGFloat((y * 37 + x * 13) % 255) / 255.0
                let g = CGFloat((y * 19 + x * 7) % 255) / 255.0
                let b = CGFloat((y * 23 + x * 29) % 255) / 255.0
                ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
                ctx.fill(CGRect(x: x, y: totalHeight - 1 - y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()
    }

    public static func extractFrame(
        from master: CGImage,
        viewportY: Int,
        viewportHeight: Int = 300,
        headerHeight: Int = 60,
        footerHeight: Int = 40,
        scrollbarThumbY: Int? = nil,
        scrollbarWidth: Int = 24
    ) -> CGImage? {
        let width = master.width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: viewportHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // 1. Draw sliced content
        let cropRect = CGRect(x: 0, y: viewportY, width: width, height: viewportHeight)
        if let slice = master.cropping(to: cropRect) {
            ctx.draw(slice, in: CGRect(x: 0, y: 0, width: width, height: viewportHeight))
        }

        // 2. Fixed stationary header at top
        ctx.setFillColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: viewportHeight - headerHeight, width: width, height: headerHeight))

        // 3. Fixed stationary footer at bottom
        ctx.setFillColor(red: 0.1, green: 0.15, blue: 0.2, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: footerHeight))

        // 4. Overwrite right scrollbar
        if let thumbY = scrollbarThumbY {
            ctx.setFillColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
            ctx.fill(CGRect(x: width - scrollbarWidth, y: 0, width: scrollbarWidth, height: viewportHeight))
            ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            let cgThumbY = max(0, viewportHeight - 40 - thumbY)
            ctx.fill(CGRect(x: width - scrollbarWidth + 2, y: cgThumbY, width: scrollbarWidth - 4, height: 40))
        }

        return ctx.makeImage()
    }
}

// MARK: - ImageStitcher Tests

public struct ImageStitcherTests {

    public static func run() {
        TestHarness.startSuite("ImageStitcher & Vertical Offset Deduction")

        testSimulatorContracts()
        testSyntheticFrameOffsetAccuracy()
        testScrollbarStripExclusion()
        testStickyHeaderAndFooterDeduplication()
        testZeroDeltaAutoStop()
        testMaxScrollHeightClamping()
        testGroundTruthPixelReconstruction()
        testErrorHandling()
    }

    // MARK: - Test 1: Algorithmic Simulator Baseline
    private static func testSimulatorContracts() {
        let width = 400
        let height = 300
        let headerH = 80
        let footerH = 40
        let scrollbarW = 24

        var frame1 = Array(repeating: Array(repeating: UInt8(0), count: width), count: height)
        for r in 0..<height {
            for c in 0..<width {
                if r < headerH {
                    frame1[r][c] = UInt8((r * 3) % 255)
                } else if r >= height - footerH {
                    frame1[r][c] = UInt8(200)
                } else {
                    frame1[r][c] = UInt8((r + c) % 255)
                }
                if c >= width - scrollbarW {
                    frame1[r][c] = (r >= 10 && r <= 50) ? UInt8(100) : UInt8(240)
                }
            }
        }

        let trueDisplacement = 100
        var frame2 = Array(repeating: Array(repeating: UInt8(0), count: width), count: height)
        for r in 0..<height {
            for c in 0..<width {
                if r < headerH {
                    frame2[r][c] = UInt8((r * 3) % 255)
                } else if r >= height - footerH {
                    frame2[r][c] = UInt8(200)
                } else {
                    let virtualY = r + trueDisplacement
                    frame2[r][c] = UInt8((virtualY + c) % 255)
                }
                if c >= width - scrollbarW {
                    frame2[r][c] = (r >= 80 && r <= 120) ? UInt8(100) : UInt8(240)
                }
            }
        }

        var headerRowsMatch = true
        for r in 0..<headerH {
            for c in 0..<(width - scrollbarW) {
                if frame1[r][c] != frame2[r][c] {
                    headerRowsMatch = false
                    break
                }
            }
        }
        TestHarness.assertTrue(headerRowsMatch, "Detected stationary sticky header across consecutive simulator frames")

        var footerRowsMatch = true
        for r in (height - footerH)..<height {
            for c in 0..<(width - scrollbarW) {
                if frame1[r][c] != frame2[r][c] {
                    footerRowsMatch = false
                    break
                }
            }
        }
        TestHarness.assertTrue(footerRowsMatch, "Detected stationary sticky footer across consecutive simulator frames")
    }

    // MARK: - Test 2: Vertical Offset Accuracy on Real CGImage Frames
    private static func testSyntheticFrameOffsetAccuracy() {
        guard let master = SyntheticFrameGenerator.createMasterCanvas(width: 400, totalHeight: 1200) else {
            TestHarness.recordFail("testSyntheticFrameOffsetAccuracy", reason: "Failed to generate master synthetic canvas")
            return
        }

        let displacements = [50, 100, 120]
        for dy in displacements {
            guard let f1 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: 300),
                  let f2 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: dy, viewportHeight: 300) else {
                TestHarness.recordFail("testSyntheticFrameOffsetAccuracy", reason: "Failed to extract frames for dy=\(dy)")
                continue
            }

            let effectiveW = 400 - 24
            let est = ImageStitcher.estimateVerticalOffset(
                f1: f1,
                f2: f2,
                effectiveWidth: effectiveW,
                headerH: 60,
                footerH: 40
            )
            TestHarness.assertEqual(est.offset, dy, "Vertical offset accurately estimated as \(dy)px")
            TestHarness.assertFalse(est.isZeroDelta, "Not zero-delta when dy=\(dy)")
            TestHarness.assertTrue(est.confidence > 0.85, "High confidence for dy=\(dy)")
        }
    }

    // MARK: - Test 3: Scrollbar Strip Exclusion
    private static func testScrollbarStripExclusion() {
        guard let master = SyntheticFrameGenerator.createMasterCanvas(width: 400, totalHeight: 1200) else {
            TestHarness.recordFail("testScrollbarStripExclusion", reason: "Failed to generate master synthetic canvas")
            return
        }

        // Frame 1 has scrollbar thumb at Y=10
        // Frame 2 has scrollbar thumb shifted to Y=120 (differing displacement from content dy=80)
        let contentDisplacement = 80
        guard let f1 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: 300, scrollbarThumbY: 10),
              let f2 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: contentDisplacement, viewportHeight: 300, scrollbarThumbY: 120) else {
            TestHarness.recordFail("testScrollbarStripExclusion", reason: "Failed to extract scrollbar frames")
            return
        }

        let effectiveW = 400 - 24
        let est = ImageStitcher.estimateVerticalOffset(
            f1: f1,
            f2: f2,
            effectiveWidth: effectiveW,
            headerH: 60,
            footerH: 40
        )
        TestHarness.assertEqual(est.offset, contentDisplacement, "Offset is 80px despite moving scrollbar thumb on right edge")
    }

    // MARK: - Test 4: Sticky Header and Footer Deduplication
    private static func testStickyHeaderAndFooterDeduplication() {
        guard let master = SyntheticFrameGenerator.createMasterCanvas(width: 400, totalHeight: 1200) else {
            TestHarness.recordFail("testStickyHeaderAndFooterDeduplication", reason: "Failed to generate master synthetic canvas")
            return
        }

        guard let f1 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: 300),
              let f2 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 80, viewportHeight: 300),
              let f3 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 160, viewportHeight: 300) else {
            TestHarness.recordFail("testStickyHeaderAndFooterDeduplication", reason: "Failed to extract 3 frames")
            return
        }

        let headerH = ImageStitcher.detectStationaryHeader(f1: f1, f2: f2, effectiveWidth: 400 - 24, maxHeaderH: 100)
        TestHarness.assertEqual(headerH, 60, "Detected stationary sticky header height exactly 60px")

        let footerH = ImageStitcher.detectStationaryFooter(f1: f1, f2: f2, effectiveWidth: 400 - 24, maxFooterH: 80)
        TestHarness.assertEqual(footerH, 40, "Detected stationary sticky footer height exactly 40px")

        let options = StitchOptions(
            scrollbarStripWidth: 24,
            headerDedupHeight: 60,
            footerDedupHeight: 40,
            maxScrollHeightPx: 15000,
            scaleFactor: 1.0
        )

        do {
            let result = try ImageStitcher.stitch(frames: [f1, f2, f3], options: options)
            TestHarness.assertEqual(result.deduplicatedHeaderHeight, 60.0, "Deduplicated header recorded as 60px")
            TestHarness.assertEqual(result.deduplicatedFooterHeight, 40.0, "Deduplicated footer recorded as 40px")
            // Total height = initial frame height (300) + dy1 (80) + dy2 (80) = 460
            TestHarness.assertEqual(result.totalHeight, 460.0, "Total stitched height equals 460px (300 + 80 + 80)")
            TestHarness.assertEqual(result.image.height, 460, "CGImage height matches 460px")
            TestHarness.assertFalse(result.isClampedToMaxHeight, "Image is not clamped")
        } catch {
            TestHarness.recordFail("testStickyHeaderAndFooterDeduplication", reason: "Stitch failed with error: \(error.localizedDescription)")
        }
    }

    // MARK: - Test 5: Zero-Delta Auto-Stop on End of Page
    private static func testZeroDeltaAutoStop() {
        guard let master = SyntheticFrameGenerator.createMasterCanvas(width: 400, totalHeight: 600) else {
            TestHarness.recordFail("testZeroDeltaAutoStop", reason: "Failed to generate master synthetic canvas")
            return
        }

        // Two identical frames at page bottom
        guard let f1 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 300, viewportHeight: 300),
              let f2 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 300, viewportHeight: 300) else {
            TestHarness.recordFail("testZeroDeltaAutoStop", reason: "Failed to extract identical frames")
            return
        }

        let est = ImageStitcher.estimateVerticalOffset(
            f1: f1,
            f2: f2,
            effectiveWidth: 400 - 24,
            headerH: 60,
            footerH: 40
        )
        TestHarness.assertTrue(est.isZeroDelta, "Identical consecutive frames detected as zero-delta")
        TestHarness.assertEqual(est.offset, 0, "Zero-delta offset is 0")
    }

    // MARK: - Test 6: Max Scroll Height Clamping
    private static func testMaxScrollHeightClamping() {
        guard let master = SyntheticFrameGenerator.createMasterCanvas(width: 400, totalHeight: 2000) else {
            TestHarness.recordFail("testMaxScrollHeightClamping", reason: "Failed to generate master synthetic canvas")
            return
        }

        var frames: [CGImage] = []
        for i in 0..<8 {
            if let f = SyntheticFrameGenerator.extractFrame(from: master, viewportY: i * 80, viewportHeight: 300) {
                frames.append(f)
            }
        }

        let options = StitchOptions(
            scrollbarStripWidth: 24,
            headerDedupHeight: 60,
            footerDedupHeight: 40,
            maxScrollHeightPx: 5000,
            scaleFactor: 1.0
        )
        TestHarness.assertEqual(options.maxScrollHeightPx, 5000.0, "maxScrollHeightPx bound to minimum 5,000 px")

        do {
            let result = try ImageStitcher.stitch(frames: frames, options: options)
            TestHarness.assertEqual(result.totalHeight, 860.0, "Result height 860px is within 5000px ceiling")
            TestHarness.assertFalse(result.isClampedToMaxHeight, "Not clamped when below ceiling")
        } catch {
            TestHarness.recordFail("testMaxScrollHeightClamping", reason: "Stitch failed: \(error)")
        }
    }

    // MARK: - Test 7: Ground-Truth Pixel Reconstruction
    private static func testGroundTruthPixelReconstruction() {
        guard let master = SyntheticFrameGenerator.createMasterCanvas(width: 400, totalHeight: 1000) else {
            TestHarness.recordFail("testGroundTruthPixelReconstruction", reason: "Failed to create master canvas")
            return
        }

        guard let f1 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: 300, scrollbarThumbY: 10),
              let f2 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 100, viewportHeight: 300, scrollbarThumbY: 70) else {
            TestHarness.recordFail("testGroundTruthPixelReconstruction", reason: "Failed to extract frames for reconstruction")
            return
        }

        let options = StitchOptions(
            scrollbarStripWidth: 24,
            headerDedupHeight: 60,
            footerDedupHeight: 40,
            maxScrollHeightPx: 15000,
            scaleFactor: 1.0
        )

        do {
            let result = try ImageStitcher.stitch(frames: [f1, f2], options: options)
            TestHarness.assertEqual(result.totalHeight, 400.0, "Total height is 400px (300 + 100)")

            let widthToCompare = 400 - 24
            let compareHeight = 300
            guard let masterSlice = master.cropping(to: CGRect(x: 0, y: 60, width: widthToCompare, height: compareHeight)),
                  let resultSlice = result.image.cropping(to: CGRect(x: 0, y: 60, width: widthToCompare, height: compareHeight)) else {
                TestHarness.recordFail("testGroundTruthPixelReconstruction", reason: "Failed to crop comparison slices")
                return
            }

            var masterBytes = [UInt8](repeating: 0, count: widthToCompare * compareHeight * 4)
            var resultBytes = [UInt8](repeating: 0, count: widthToCompare * compareHeight * 4)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

            let ctxM = CGContext(data: &masterBytes, width: widthToCompare, height: compareHeight, bitsPerComponent: 8, bytesPerRow: widthToCompare * 4, space: colorSpace, bitmapInfo: bitmapInfo)!
            let ctxR = CGContext(data: &resultBytes, width: widthToCompare, height: compareHeight, bitsPerComponent: 8, bytesPerRow: widthToCompare * 4, space: colorSpace, bitmapInfo: bitmapInfo)!
            ctxM.draw(masterSlice, in: CGRect(x: 0, y: 0, width: widthToCompare, height: compareHeight))
            ctxR.draw(resultSlice, in: CGRect(x: 0, y: 0, width: widthToCompare, height: compareHeight))

            var pixelDiffs = 0
            for i in 0..<masterBytes.count {
                if masterBytes[i] != resultBytes[i] {
                    pixelDiffs += 1
                }
            }
            TestHarness.assertEqual(pixelDiffs, 0, "Ground-truth pixel reconstruction has exactly 0 differences")
        } catch {
            TestHarness.recordFail("testGroundTruthPixelReconstruction", reason: "Stitch failed: \(error)")
        }
    }

    // MARK: - Test 8: Error Handling
    private static func testErrorHandling() {
        let emptyFrames: [CGImage] = []
        do {
            _ = try ImageStitcher.stitch(frames: emptyFrames)
            TestHarness.recordFail("Empty frames error handling", reason: "Expected stitch to throw emptyFrames error")
        } catch {
            TestHarness.recordPass("Empty frames array throws emptyFrames error")
        }

        guard let master = SyntheticFrameGenerator.createMasterCanvas(width: 400, totalHeight: 600),
              let f1 = SyntheticFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: 300),
              let f2 = SyntheticFrameGenerator.createMasterCanvas(width: 200, totalHeight: 300) else {
            return
        }

        do {
            _ = try ImageStitcher.stitch(frames: [f1, f2])
            TestHarness.recordFail("Mismatched dimensions error handling", reason: "Expected stitch to throw invalidDimensions error")
        } catch {
            TestHarness.recordPass("Mismatched frame widths throw invalidDimensions error")
        }
    }
}
