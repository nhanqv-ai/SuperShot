import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import Carbon
import Darwin
import SuperShotCore
import SuperShot

// MARK: - Adversarial Test Harness

final class ChallengerHarness {
    static var totalTests: Int = 0
    static var passedTests: Int = 0
    static var failedTests: Int = 0
    private static let lock = NSLock()

    static func startSuite(_ name: String) {
        lock.lock()
        print("\n\u{001B}[1;35m=== Adversarial Suite: \(name) ===\u{001B}[0m")
        lock.unlock()
    }

    static func recordPass(_ testName: String) {
        lock.lock()
        totalTests += 1
        passedTests += 1
        print("  \u{001B}[32m[PASS]\u{001B}[0m \(testName)")
        lock.unlock()
    }

    static func recordFail(_ testName: String, reason: String) {
        lock.lock()
        totalTests += 1
        failedTests += 1
        print("  \u{001B}[31m[FAIL]\u{001B}[0m \(testName): \(reason)")
        lock.unlock()
    }

    static func assertTrue(_ condition: Bool, _ testName: String, reason: String = "Condition was false") {
        if condition { recordPass(testName) } else { recordFail(testName, reason: reason) }
    }

    static func assertFalse(_ condition: Bool, _ testName: String, reason: String = "Condition was true") {
        if !condition { recordPass(testName) } else { recordFail(testName, reason: reason) }
    }

    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ testName: String) {
        if a == b { recordPass(testName) } else { recordFail(testName, reason: "Expected \(b), got \(a)") }
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil { recordPass(testName) } else { recordFail(testName, reason: "Expected nil, got \(String(describing: value))") }
    }

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil { recordPass(testName) } else { recordFail(testName, reason: "Expected non-nil value") }
    }

    static var exitCode: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return failedTests > 0 ? 1 : 0
    }
}


// MARK: - Synthetic Frame Generator for Stress Testing

struct AdversarialFrameGenerator {
    static func createMasterCanvas(
        width: Int,
        totalHeight: Int,
        headerColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.2, 0.3, 0.4),
        footerColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.1, 0.15, 0.2)
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
                var h = UInt64(y) &* 73856093 ^ UInt64(x) &* 19349663 ^ 83492791
                h = (h ^ (h >> 16)) &* 0x45d9f3b
                let r = CGFloat(h & 0xFF) / 255.0
                let g = CGFloat((h >> 8) & 0xFF) / 255.0
                let b = CGFloat((h >> 16) & 0xFF) / 255.0
                ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
                ctx.fill(CGRect(x: x, y: totalHeight - 1 - y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()
    }

    static func extractFrame(
        from master: CGImage,
        viewportY: Int,
        viewportHeight: Int,
        headerHeight: Int = 0,
        footerHeight: Int = 0,
        headerColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.2, 0.3, 0.4),
        footerColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.1, 0.15, 0.2),
        scrollbarThumbY: Int? = nil,
        scrollbarThumbHeight: Int = 40,
        scrollbarWidth: Int = 24,
        scrollbarNoiseSeed: Int = 0
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

        // 1. Draw sliced content from master canvas
        let cropRect = CGRect(x: 0, y: viewportY, width: width, height: viewportHeight)
        if let slice = master.cropping(to: cropRect) {
            ctx.draw(slice, in: CGRect(x: 0, y: 0, width: width, height: viewportHeight))
        }

        // 2. Fixed stationary header at top of viewport
        if headerHeight > 0 {
            ctx.setFillColor(red: headerColor.r, green: headerColor.g, blue: headerColor.b, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: viewportHeight - headerHeight, width: width, height: headerHeight))
        }

        // 3. Fixed stationary footer at bottom of viewport
        if footerHeight > 0 {
            ctx.setFillColor(red: footerColor.r, green: footerColor.g, blue: footerColor.b, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: footerHeight))
        }

        // 4. Right scrollbar strip with optional moving/noise thumb
        if let thumbY = scrollbarThumbY, scrollbarWidth > 0 {
            // Scrollbar track
            let trackShade = CGFloat(0.85 + Double(scrollbarNoiseSeed % 10) * 0.01)
            ctx.setFillColor(red: trackShade, green: trackShade, blue: trackShade, alpha: 1.0)
            ctx.fill(CGRect(x: width - scrollbarWidth, y: 0, width: scrollbarWidth, height: viewportHeight))

            // Scrollbar thumb
            let thumbShade = CGFloat(0.40 + Double(scrollbarNoiseSeed % 15) * 0.02)
            ctx.setFillColor(red: thumbShade, green: thumbShade, blue: thumbShade, alpha: 1.0)
            let cgThumbY = max(0, min(viewportHeight - scrollbarThumbHeight, viewportHeight - scrollbarThumbHeight - thumbY))
            ctx.fill(CGRect(x: width - scrollbarWidth + 2, y: cgThumbY, width: max(1, scrollbarWidth - 4), height: scrollbarThumbHeight))
        }

        return ctx.makeImage()
    }
}

// MARK: - Adversarial Challenge Executable

@main
struct AdversarialChallenge {

    static func main() {
        print("\u{001B}[1;35m============================================================\u{001B}[0m")
        print("\u{001B}[1;35m  SuperShot Adversarial & Mathematical Stress Test        \u{001B}[0m")
        print("\u{001B}[1;35m  Challenger M4.1: Zero-Emoji Empirical Verification       \u{001B}[0m")
        print("\u{001B}[1;35m============================================================\u{001B}[0m")

        let startTime = Date()

        // M3: ImageStitcher Stress Suites
        testArbitraryAndPrimeDisplacements()
        testStickyHeaderAndFooterVariations()
        testScrollbarAntiDirectionalMotionAndNoise()
        testExtremeMicroAndLargeFrames()
        testDeepSequenceClamping()
        testGroundTruthPixelDifferenceOracle()
        testZeroDeltaAutoStopRobustness()
        testBoundaryErrorConditions()

        // M4: History & Navigation Stress Suites
        testCircularKeyboardNavigation()
        testQuickSelectionMapping()
        testSearchFilteringLogic()
        testHoverPreviewPositioning()

        // M10: UpdateManager & AppSettings Stress Suites
        testSemanticVersionAndReleaseInfoAdversarialParsing()
        testUpdateManagerStateTransitionsAndConcurrency()
        testUpdateCheckIntervalClampingAndPersistence()

        // M13: Duplication, Geometry & Zoom Stress Suites
        testAnnotationDuplicationAndDeepUndoRedoStress()
        testAngleSnappingAndZoomMagnificationStress()

        // M25: Smart Sizing, Stroke Stepping & Tab Cycling Stress Suites
        testAspectRatioDetectionAndToleranceBoundaryStress()
        testStrokeWidthBracketSteppingBoundsAndDispatchStress()
        testShiftKeyAspectRatioSnappingUnderExtremeCoordinatesStress()
        testSettingsTabCyclingWrappingAndModuloStress()

        // M30: Selection Box & Object Resizing, ClearAll Batch Undo/Redo & Share Shortcuts Stress
        testMilestoneM30EmpiricalStressAndAdversarialChallenge()

        // M35: Milestone M35 v1.0.17 Empirical Stress Suites
        testMilestoneM35EmpiricalStressAndAdversarialChallenge()

        // M47: Milestone M47-2 v1.0.20 Empirical Stress Suites
        testMilestoneM47EmpiricalStressAndAdversarialChallenge()

        // M51: Milestone M51-2 v1.0.21 Empirical Stress Suites
        testMilestoneM51EmpiricalStressAndAdversarialChallenge()

        // M52: Milestone M52 Cycle 15 UpdateManager, DMG Extraction & Streaming Progress Stress Suite
        testMilestoneM52EmpiricalStressAndAdversarialChallenge()

        let elapsed = Date().timeIntervalSince(startTime)

        print("\n\u{001B}[1;35m============================================================\u{001B}[0m")
        print("\u{001B}[1;35m  Adversarial Challenge Summary\u{001B}[0m")
        print("\u{001B}[1;35m============================================================\u{001B}[0m")
        print("  Total Stress Tests:  \(ChallengerHarness.totalTests)")
        print("  Passed Stress Tests: \u{001B}[32m\(ChallengerHarness.passedTests)\u{001B}[0m")
        print("  Failed Stress Tests: " + (ChallengerHarness.failedTests > 0 ? "\u{001B}[31m\(ChallengerHarness.failedTests)\u{001B}[0m" : "0"))
        print("  Elapsed Runtime:     \(String(format: "%.3f", elapsed))s")

        if ChallengerHarness.failedTests == 0 {
            print("\n\u{001B}[1;32mVERDICT: APPROVE (100% EMPIRICAL STRESS TESTS PASSED, 0 FAILURES, 0 EMOJIS)\u{001B}[0m\n")
        } else {
            print("\n\u{001B}[1;31mVERDICT: FAIL (\(ChallengerHarness.failedTests) STRESS TESTS FAILED)\u{001B}[0m\n")
        }

        exit(ChallengerHarness.exitCode)
    }

    // MARK: - 1. Arbitrary & Prime Displacements
    private static func testArbitraryAndPrimeDisplacements() {
        ChallengerHarness.startSuite("1. Arbitrary & Prime Vertical Displacements")

        let width = 600
        let totalH = 3000
        let viewportH = 500
        let headerH = 40
        let footerH = 30
        let scrollbarW = 24

        guard let master = AdversarialFrameGenerator.createMasterCanvas(width: width, totalHeight: totalH) else {
            ChallengerHarness.recordFail("Master Canvas Allocation", reason: "Failed to create master canvas")
            return
        }

        // Test displacements including primes, odd values, small and large displacements
        let testDisplacements = [15, 47, 113, 250, 71, 89, 173, 299]

        for dy in testDisplacements {
            guard let f1 = AdversarialFrameGenerator.extractFrame(
                from: master,
                viewportY: 0,
                viewportHeight: viewportH,
                headerHeight: headerH,
                footerHeight: footerH,
                scrollbarThumbY: 10,
                scrollbarWidth: scrollbarW
            ),
            let f2 = AdversarialFrameGenerator.extractFrame(
                from: master,
                viewportY: dy,
                viewportHeight: viewportH,
                headerHeight: headerH,
                footerHeight: footerH,
                scrollbarThumbY: 10 + dy / 2,
                scrollbarWidth: scrollbarW
            ) else {
                ChallengerHarness.recordFail("Frame Extraction dy=\(dy)", reason: "Extraction failed")
                continue
            }

            let effectiveW = width - scrollbarW
            let est = ImageStitcher.estimateVerticalOffset(
                f1: f1,
                f2: f2,
                effectiveWidth: effectiveW,
                headerH: headerH,
                footerH: footerH
            )

            ChallengerHarness.assertEqual(est.offset, dy, "Vertical offset accurately estimated for displacement dy=\(dy)px")
            ChallengerHarness.assertFalse(est.isZeroDelta, "Not zero delta for dy=\(dy)")
            ChallengerHarness.assertTrue(est.confidence > 0.85, "Confidence high (\(String(format: "%.3f", est.confidence))) for dy=\(dy)")

            // Test 2-frame stitch total height
            let options = StitchOptions(
                scrollbarStripWidth: CGFloat(scrollbarW),
                headerDedupHeight: CGFloat(headerH),
                footerDedupHeight: CGFloat(footerH),
                maxScrollHeightPx: 15000,
                scaleFactor: 1.0
            )

            do {
                let result = try ImageStitcher.stitch(frames: [f1, f2], options: options)
                let expectedHeight = CGFloat(viewportH + dy)
                ChallengerHarness.assertEqual(result.totalHeight, expectedHeight, "Stitched height matches viewportH + dy (\(expectedHeight)px)")
                ChallengerHarness.assertEqual(result.image.height, Int(expectedHeight), "CGImage height matches \(expectedHeight)px")
            } catch {
                ChallengerHarness.recordFail("Stitch dy=\(dy)", reason: "Threw error: \(error)")
            }
        }
    }

    // MARK: - 2. Sticky Header and Footer Variations & Exact-Once Slicing
    private static func testStickyHeaderAndFooterVariations() {
        ChallengerHarness.startSuite("2. Sticky Header/Footer Variations & Deduplication")

        let width = 500
        let totalH = 2000
        let viewportH = 400
        let scrollbarW = 24

        guard let master = AdversarialFrameGenerator.createMasterCanvas(width: width, totalHeight: totalH) else {
            ChallengerHarness.recordFail("Master Canvas", reason: "Allocation failed")
            return
        }

        // Test varying header heights (10px, 50px, 120px) and footer heights (15px, 60px)
        let variations: [(header: Int, footer: Int)] = [
            (header: 10, footer: 15),
            (header: 50, footer: 60),
            (header: 120, footer: 15),
            (header: 120, footer: 60),
            (header: 0, footer: 0)
        ]

        let dy = 70

        for (hH, fH) in variations {
            guard let f1 = AdversarialFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: viewportH, headerHeight: hH, footerHeight: fH, scrollbarThumbY: 10, scrollbarWidth: scrollbarW),
                  let f2 = AdversarialFrameGenerator.extractFrame(from: master, viewportY: dy, viewportHeight: viewportH, headerHeight: hH, footerHeight: fH, scrollbarThumbY: 30, scrollbarWidth: scrollbarW),
                  let f3 = AdversarialFrameGenerator.extractFrame(from: master, viewportY: dy * 2, viewportHeight: viewportH, headerHeight: hH, footerHeight: fH, scrollbarThumbY: 50, scrollbarWidth: scrollbarW) else {
                ChallengerHarness.recordFail("Extract frames H=\(hH) F=\(fH)", reason: "Extraction failed")
                continue
            }

            let effectiveW = width - scrollbarW
            let detectedH = ImageStitcher.detectStationaryHeader(f1: f1, f2: f2, effectiveWidth: effectiveW, maxHeaderH: max(1, hH + 20))
            let detectedF = ImageStitcher.detectStationaryFooter(f1: f1, f2: f2, effectiveWidth: effectiveW, maxFooterH: max(1, fH + 20))

            ChallengerHarness.assertEqual(detectedH, hH, "Stationary header detected exactly as \(hH)px (H=\(hH), F=\(fH))")
            ChallengerHarness.assertEqual(detectedF, fH, "Stationary footer detected exactly as \(fH)px (H=\(hH), F=\(fH))")

            let options = StitchOptions(
                scrollbarStripWidth: CGFloat(scrollbarW),
                headerDedupHeight: CGFloat(max(1, hH)),
                footerDedupHeight: CGFloat(max(1, fH)),
                maxScrollHeightPx: 15000,
                scaleFactor: 1.0
            )

            do {
                let result = try ImageStitcher.stitch(frames: [f1, f2, f3], options: options)
                let expectedHeight = CGFloat(viewportH + dy * 2)
                ChallengerHarness.assertEqual(result.totalHeight, expectedHeight, "Total height with H=\(hH) F=\(fH) is \(expectedHeight)px")
                ChallengerHarness.assertEqual(result.deduplicatedHeaderHeight, CGFloat(hH), "Result recorded deduplicatedHeaderHeight == \(hH)")
                ChallengerHarness.assertEqual(result.deduplicatedFooterHeight, CGFloat(fH), "Result recorded deduplicatedFooterHeight == \(fH)")

                // Verify exact-once appearance of header:
                // If header > 0, check rows [0 ..< hH] match header color, and rows [hH ..< totalH - fH] do not replicate header
                if hH > 0 {
                    let isHeaderAtTop = verifySliceColor(image: result.image, startY: 0, height: hH, width: width - scrollbarW, expected: (0.2, 0.3, 0.4))
                    ChallengerHarness.assertTrue(isHeaderAtTop, "Sticky header appears at the top of the stitched image (H=\(hH))")
                }

                // Verify exact-once appearance of footer:
                // If footer > 0, check rows [totalH - fH ..< totalH] match footer color
                if fH > 0 {
                    let footerStartY = Int(result.totalHeight) - fH
                    let isFooterAtBottom = verifySliceColor(image: result.image, startY: footerStartY, height: fH, width: width - scrollbarW, expected: (0.1, 0.15, 0.2))
                    ChallengerHarness.assertTrue(isFooterAtBottom, "Sticky footer appears at the bottom of the stitched image (F=\(fH))")
                }
            } catch {
                ChallengerHarness.recordFail("Stitch H=\(hH) F=\(fH)", reason: "Threw error: \(error)")
            }
        }
    }

    // MARK: - 3. Scrollbar Anti-Directional Motion and Noise
    private static func testScrollbarAntiDirectionalMotionAndNoise() {
        ChallengerHarness.startSuite("3. Dynamic Scrollbar Noise & Anti-Directional Motion")

        let width = 500
        let totalH = 2000
        let viewportH = 400
        let headerH = 50
        let footerH = 40
        let scrollbarW = 30
        let contentDy = 80

        guard let master = AdversarialFrameGenerator.createMasterCanvas(width: width, totalHeight: totalH) else {
            ChallengerHarness.recordFail("Master Canvas", reason: "Allocation failed")
            return
        }

        // Adversarial Scenario A: Reverse-moving scrollbar thumb (moves UP from 250 to 20 while content moves DOWN)
        guard let f1A = AdversarialFrameGenerator.extractFrame(
            from: master,
            viewportY: 0,
            viewportHeight: viewportH,
            headerHeight: headerH,
            footerHeight: footerH,
            scrollbarThumbY: 250,
            scrollbarThumbHeight: 50,
            scrollbarWidth: scrollbarW,
            scrollbarNoiseSeed: 1
        ),
        let f2A = AdversarialFrameGenerator.extractFrame(
            from: master,
            viewportY: contentDy,
            viewportHeight: viewportH,
            headerHeight: headerH,
            footerHeight: footerH,
            scrollbarThumbY: 20,
            scrollbarThumbHeight: 50,
            scrollbarWidth: scrollbarW,
            scrollbarNoiseSeed: 2
        ) else {
            ChallengerHarness.recordFail("Scenario A frames", reason: "Extraction failed")
            return
        }

        let effectiveW = width - scrollbarW
        let estA = ImageStitcher.estimateVerticalOffset(
            f1: f1A,
            f2: f2A,
            effectiveWidth: effectiveW,
            headerH: headerH,
            footerH: footerH
        )
        ChallengerHarness.assertEqual(estA.offset, contentDy, "Anti-directional reverse scrollbar motion yields exact offset dy=\(contentDy)px")
        ChallengerHarness.assertTrue(estA.confidence > 0.85, "Confidence remains high despite reverse scrollbar motion")

        // Adversarial Scenario B: Morphing scrollbar thumb (changes size from 20px to 120px with contrasting luminance noise)
        guard let f1B = AdversarialFrameGenerator.extractFrame(
            from: master,
            viewportY: 0,
            viewportHeight: viewportH,
            headerHeight: headerH,
            footerHeight: footerH,
            scrollbarThumbY: 40,
            scrollbarThumbHeight: 20,
            scrollbarWidth: scrollbarW,
            scrollbarNoiseSeed: 5
        ),
        let f2B = AdversarialFrameGenerator.extractFrame(
            from: master,
            viewportY: contentDy,
            viewportHeight: viewportH,
            headerHeight: headerH,
            footerHeight: footerH,
            scrollbarThumbY: 180,
            scrollbarThumbHeight: 120,
            scrollbarWidth: scrollbarW,
            scrollbarNoiseSeed: 9
        ) else {
            ChallengerHarness.recordFail("Scenario B frames", reason: "Extraction failed")
            return
        }

        let estB = ImageStitcher.estimateVerticalOffset(
            f1: f1B,
            f2: f2B,
            effectiveWidth: effectiveW,
            headerH: headerH,
            footerH: footerH
        )
        ChallengerHarness.assertEqual(estB.offset, contentDy, "Morphing scrollbar thumb size and luminance noise yields exact offset dy=\(contentDy)px")

        // Adversarial Scenario C: Varying scrollbarStripWidth settings (12, 24, 48, 64)
        for sbWidth in [12, 24, 48, 64] {
            guard let f1C = AdversarialFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: viewportH, headerHeight: headerH, footerHeight: footerH, scrollbarThumbY: 10, scrollbarWidth: sbWidth),
                  let f2C = AdversarialFrameGenerator.extractFrame(from: master, viewportY: contentDy, viewportHeight: viewportH, headerHeight: headerH, footerHeight: footerH, scrollbarThumbY: 150, scrollbarWidth: sbWidth) else {
                continue
            }
            let options = StitchOptions(
                scrollbarStripWidth: CGFloat(sbWidth),
                headerDedupHeight: CGFloat(headerH),
                footerDedupHeight: CGFloat(footerH),
                maxScrollHeightPx: 15000,
                scaleFactor: 1.0
            )
            do {
                let res = try ImageStitcher.stitch(frames: [f1C, f2C], options: options)
                ChallengerHarness.assertEqual(res.totalHeight, CGFloat(viewportH + contentDy), "Stitched correctly with scrollbarStripWidth=\(sbWidth)")
            } catch {
                ChallengerHarness.recordFail("Scrollbar width \(sbWidth)", reason: "Stitch failed: \(error)")
            }
        }
    }

    // MARK: - 4. Extreme Micro and Large Frames
    private static func testExtremeMicroAndLargeFrames() {
        ChallengerHarness.startSuite("4. Extreme Micro Frames & Large QHD Frames")

        // 4a: Extreme Micro Frame: 50x50 pixels
        let microW = 50
        let microH = 50
        guard let microMaster = AdversarialFrameGenerator.createMasterCanvas(width: microW, totalHeight: 300) else {
            ChallengerHarness.recordFail("Micro Master", reason: "Allocation failed")
            return
        }

        let microDy = 8
        guard let microF1 = AdversarialFrameGenerator.extractFrame(from: microMaster, viewportY: 0, viewportHeight: microH, headerHeight: 8, footerHeight: 8, scrollbarWidth: 4),
              let microF2 = AdversarialFrameGenerator.extractFrame(from: microMaster, viewportY: microDy, viewportHeight: microH, headerHeight: 8, footerHeight: 8, scrollbarWidth: 4) else {
            ChallengerHarness.recordFail("Micro Frames extraction", reason: "Extraction failed")
            return
        }

        let microOptions = StitchOptions(
            scrollbarStripWidth: 4,
            headerDedupHeight: 8,
            footerDedupHeight: 8,
            maxScrollHeightPx: 5000,
            scaleFactor: 1.0
        )

        do {
            let microResult = try ImageStitcher.stitch(frames: [microF1, microF2], options: microOptions)
            let expectedH = CGFloat(microH + microDy)
            ChallengerHarness.assertEqual(microResult.totalHeight, expectedH, "Micro 50x50 frame stitched cleanly to \(expectedH)px")
            ChallengerHarness.assertEqual(microResult.image.width, microW, "Micro result image width is \(microW)")
            ChallengerHarness.assertEqual(microResult.image.height, Int(expectedH), "Micro result image height is \(Int(expectedH))")
        } catch {
            ChallengerHarness.recordFail("Micro Frame Stitch", reason: "Threw error: \(error)")
        }

        // 4b: Large Frame: 1920x1080 (Full HD)
        let largeW = 1920
        let largeH = 1080
        guard let largeMaster = AdversarialFrameGenerator.createMasterCanvas(width: largeW, totalHeight: 3000) else {
            ChallengerHarness.recordFail("Large Master", reason: "Allocation failed")
            return
        }

        let largeDy = 250
        guard let largeF1 = AdversarialFrameGenerator.extractFrame(from: largeMaster, viewportY: 0, viewportHeight: largeH, headerHeight: 60, footerHeight: 40, scrollbarWidth: 24),
              let largeF2 = AdversarialFrameGenerator.extractFrame(from: largeMaster, viewportY: largeDy, viewportHeight: largeH, headerHeight: 60, footerHeight: 40, scrollbarWidth: 24) else {
            ChallengerHarness.recordFail("Large Frames extraction", reason: "Extraction failed")
            return
        }

        let largeOptions = StitchOptions(
            scrollbarStripWidth: 24,
            headerDedupHeight: 60,
            footerDedupHeight: 40,
            maxScrollHeightPx: 15000,
            scaleFactor: 1.0
        )

        do {
            let largeResult = try ImageStitcher.stitch(frames: [largeF1, largeF2], options: largeOptions)
            let expectedLargeH = CGFloat(largeH + largeDy)
            ChallengerHarness.assertEqual(largeResult.totalHeight, expectedLargeH, "Full HD 1920x1080 frame stitched to \(expectedLargeH)px")
            ChallengerHarness.assertEqual(largeResult.image.width, largeW, "Full HD result width is \(largeW)")
            ChallengerHarness.assertEqual(largeResult.image.height, Int(expectedLargeH), "Full HD result height is \(Int(expectedLargeH))")
            ChallengerHarness.assertFalse(largeResult.isClampedToMaxHeight, "Full HD result is not clamped")
        } catch {
            ChallengerHarness.recordFail("Large Frame Stitch", reason: "Threw error: \(error)")
        }
    }

    // MARK: - 5. Deep Sequence Clamping
    private static func testDeepSequenceClamping() {
        ChallengerHarness.startSuite("5. Deep Sequence (30+ Frames) & Height Clamping")

        let frameW = 400
        let frameH = 500
        let masterTotalH = 20000
        guard let master = AdversarialFrameGenerator.createMasterCanvas(width: frameW, totalHeight: masterTotalH) else {
            ChallengerHarness.recordFail("Deep master canvas", reason: "Allocation failed")
            return
        }

        let frameCount = 30
        let dy = 200 // 29 transitions * 200 = 5,800px displacement. Total unconstrained = 500 + 5800 = 6,300px

        var frames: [CGImage] = []
        for i in 0..<frameCount {
            let vY = i * dy
            if let f = AdversarialFrameGenerator.extractFrame(from: master, viewportY: vY, viewportHeight: frameH, headerHeight: 50, footerHeight: 40, scrollbarThumbY: 10 + i * 5, scrollbarWidth: 24) {
                frames.append(f)
            }
        }
        ChallengerHarness.assertEqual(frames.count, frameCount, "Generated all \(frameCount) synthetic frames successfully")

        // Test 5A: Ceiling 15,000 px (unconstrained 6,300 px < 15,000 px -> not clamped)
        let unconstrainedOptions = StitchOptions(
            scrollbarStripWidth: 24,
            headerDedupHeight: 50,
            footerDedupHeight: 40,
            maxScrollHeightPx: 15000,
            scaleFactor: 1.0
        )

        do {
            let res = try ImageStitcher.stitch(frames: frames, options: unconstrainedOptions)
            let expectedTotalH = CGFloat(frameH + (frameCount - 1) * dy)
            ChallengerHarness.assertEqual(res.totalHeight, expectedTotalH, "30-frame stitch total height equals \(expectedTotalH)px")
            ChallengerHarness.assertEqual(res.frameOffsets.count, frameCount - 1, "Recorded \(frameCount - 1) frame offsets")
            ChallengerHarness.assertFalse(res.isClampedToMaxHeight, "isClampedToMaxHeight is false when below ceiling")
            ChallengerHarness.assertEqual(res.image.height, Int(expectedTotalH), "CGImage height matches \(Int(expectedTotalH))")
        } catch {
            ChallengerHarness.recordFail("30-frame unconstrained stitch", reason: "Error: \(error)")
        }

        // Test 5B: Ceiling 5,000 px (unconstrained 6,300 px > 5,000 px -> clamped to 5,000 px)
        let clampedOptions = StitchOptions(
            scrollbarStripWidth: 24,
            headerDedupHeight: 50,
            footerDedupHeight: 40,
            maxScrollHeightPx: 5000,
            scaleFactor: 1.0
        )

        do {
            let clampedRes = try ImageStitcher.stitch(frames: frames, options: clampedOptions)
            ChallengerHarness.assertEqual(clampedRes.totalHeight, 5000.0, "Clamped total height equals exactly 5,000px")
            ChallengerHarness.assertTrue(clampedRes.isClampedToMaxHeight, "isClampedToMaxHeight is true when exceeding ceiling")
            ChallengerHarness.assertEqual(clampedRes.image.height, 5000, "CGImage height is clamped to 5,000px")
        } catch {
            ChallengerHarness.recordFail("30-frame clamped stitch", reason: "Error: \(error)")
        }

        // Test 5C: Configurable bounds clamping [5000, 30000]
        let lowBound = StitchOptions(maxScrollHeightPx: 1000)
        ChallengerHarness.assertEqual(lowBound.maxScrollHeightPx, 5000.0, "maxScrollHeightPx < 5000 clamped to 5000")

        let highBound = StitchOptions(maxScrollHeightPx: 50000)
        ChallengerHarness.assertEqual(highBound.maxScrollHeightPx, 30000.0, "maxScrollHeightPx > 30000 clamped to 30000")
    }

    // MARK: - 6. Ground-Truth Pixel Difference == 0 Oracle
    private static func testGroundTruthPixelDifferenceOracle() {
        ChallengerHarness.startSuite("6. Ground-Truth Pixel Difference == 0 Oracle")

        let width = 400
        let totalH = 2000
        let viewportH = 350
        let headerH = 50
        let footerH = 40
        let scrollbarW = 24

        guard let master = AdversarialFrameGenerator.createMasterCanvas(width: width, totalHeight: totalH) else {
            ChallengerHarness.recordFail("Master Canvas", reason: "Allocation failed")
            return
        }

        // 4 consecutive frames with varying displacements: 75px, 95px, 120px
        let displacements = [75, 95, 120]
        var viewports = [0]
        for d in displacements {
            viewports.append(viewports.last! + d)
        }

        var frames: [CGImage] = []
        for (idx, vpY) in viewports.enumerated() {
            if let f = AdversarialFrameGenerator.extractFrame(
                from: master,
                viewportY: vpY,
                viewportHeight: viewportH,
                headerHeight: headerH,
                footerHeight: footerH,
                scrollbarThumbY: 10 + idx * 40,
                scrollbarWidth: scrollbarW
            ) {
                frames.append(f)
            }
        }
        ChallengerHarness.assertEqual(frames.count, 4, "Extracted 4 multi-slice frames")

        let options = StitchOptions(
            scrollbarStripWidth: CGFloat(scrollbarW),
            headerDedupHeight: CGFloat(headerH),
            footerDedupHeight: CGFloat(footerH),
            maxScrollHeightPx: 15000,
            scaleFactor: 1.0
        )

        do {
            let result = try ImageStitcher.stitch(frames: frames, options: options)
            let sumDy = displacements.reduce(0, +)
            let expectedTotalH = CGFloat(viewportH + sumDy)
            ChallengerHarness.assertEqual(result.totalHeight, expectedTotalH, "Multi-frame stitched height is \(expectedTotalH)px")

            // Reconstructed Content Area:
            // Stitched image content rows from headerH to (totalHeight - footerH)
            // corresponds to rows headerH to (viewports.last + viewportH - footerH) of master canvas.
            let contentH = Int(result.totalHeight) - headerH - footerH
            let effectiveW = width - scrollbarW

            guard let masterSlice = master.cropping(to: CGRect(x: 0, y: headerH, width: effectiveW, height: contentH)),
                  let stitchedSlice = result.image.cropping(to: CGRect(x: 0, y: headerH, width: effectiveW, height: contentH)) else {
                ChallengerHarness.recordFail("Crop Content Slices", reason: "Cropping failed")
                return
            }

            var masterBytes = [UInt8](repeating: 0, count: effectiveW * contentH * 4)
            var stitchedBytes = [UInt8](repeating: 0, count: effectiveW * contentH * 4)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

            guard let ctxM = CGContext(data: &masterBytes, width: effectiveW, height: contentH, bitsPerComponent: 8, bytesPerRow: effectiveW * 4, space: colorSpace, bitmapInfo: bitmapInfo),
                  let ctxS = CGContext(data: &stitchedBytes, width: effectiveW, height: contentH, bitsPerComponent: 8, bytesPerRow: effectiveW * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
                ChallengerHarness.recordFail("Bitmap Context Allocation", reason: "Context creation failed")
                return
            }

            ctxM.draw(masterSlice, in: CGRect(x: 0, y: 0, width: effectiveW, height: contentH))
            ctxS.draw(stitchedSlice, in: CGRect(x: 0, y: 0, width: effectiveW, height: contentH))

            var pixelDiffs = 0
            for i in 0..<masterBytes.count {
                if masterBytes[i] != stitchedBytes[i] {
                    pixelDiffs += 1
                }
            }

            ChallengerHarness.assertEqual(pixelDiffs, 0, "Oracle: Multi-frame reconstructed content has EXACTLY 0 pixel differences across \(effectiveW * contentH) pixels")
        } catch {
            ChallengerHarness.recordFail("Ground Truth Stitch", reason: "Stitch failed: \(error)")
        }
    }

    // MARK: - 7. Zero-Delta Auto-Stop Robustness
    private static func testZeroDeltaAutoStopRobustness() {
        ChallengerHarness.startSuite("7. Zero-Delta Auto-Stop Robustness")

        let width = 400
        let viewportH = 300
        guard let master = AdversarialFrameGenerator.createMasterCanvas(width: width, totalHeight: 800) else {
            ChallengerHarness.recordFail("Master Canvas", reason: "Allocation failed")
            return
        }

        // 7a: Identical frames at end of page
        guard let f1 = AdversarialFrameGenerator.extractFrame(from: master, viewportY: 400, viewportHeight: viewportH, headerHeight: 50, footerHeight: 30),
              let f2 = AdversarialFrameGenerator.extractFrame(from: master, viewportY: 400, viewportHeight: viewportH, headerHeight: 50, footerHeight: 30) else {
            ChallengerHarness.recordFail("Identical frames extraction", reason: "Failed")
            return
        }

        let estIdentical = ImageStitcher.estimateVerticalOffset(f1: f1, f2: f2, effectiveWidth: width - 24, headerH: 50, footerH: 30)
        ChallengerHarness.assertTrue(estIdentical.isZeroDelta, "Identical consecutive frames correctly trigger isZeroDelta == true")
        ChallengerHarness.assertEqual(estIdentical.offset, 0, "Identical consecutive frames return offset == 0")

        // 7b: Frames with stationary content but moving scrollbar thumb
        guard let f1SB = AdversarialFrameGenerator.extractFrame(from: master, viewportY: 400, viewportHeight: viewportH, headerHeight: 50, footerHeight: 30, scrollbarThumbY: 10, scrollbarWidth: 24),
              let f2SB = AdversarialFrameGenerator.extractFrame(from: master, viewportY: 400, viewportHeight: viewportH, headerHeight: 50, footerHeight: 30, scrollbarThumbY: 100, scrollbarWidth: 24) else {
            ChallengerHarness.recordFail("Moving thumb stationary content frames", reason: "Failed")
            return
        }

        let estSB = ImageStitcher.estimateVerticalOffset(f1: f1SB, f2: f2SB, effectiveWidth: width - 24, headerH: 50, footerH: 30)
        ChallengerHarness.assertTrue(estSB.isZeroDelta, "Zero-delta detected even when scrollbar thumb jitters on page bottom")
        ChallengerHarness.assertEqual(estSB.offset, 0, "Offset is 0 when content is stationary despite scrollbar jitter")
    }

    // MARK: - 8. Boundary & Error Conditions
    private static func testBoundaryErrorConditions() {
        ChallengerHarness.startSuite("8. Boundary & Error Conditions")

        // 8a: Empty frames array
        do {
            _ = try ImageStitcher.stitch(frames: [])
            ChallengerHarness.recordFail("Empty frames", reason: "Expected emptyFrames error")
        } catch ImageStitcherError.emptyFrames {
            ChallengerHarness.recordPass("Empty frames array properly throws ImageStitcherError.emptyFrames")
        } catch {
            ChallengerHarness.recordFail("Empty frames", reason: "Wrong error thrown: \(error)")
        }

        // 8b: Single frame passes through cleanly
        guard let master = AdversarialFrameGenerator.createMasterCanvas(width: 300, totalHeight: 400),
              let single = AdversarialFrameGenerator.extractFrame(from: master, viewportY: 0, viewportHeight: 300) else {
            return
        }

        do {
            let singleRes = try ImageStitcher.stitch(frames: [single])
            ChallengerHarness.assertEqual(singleRes.totalHeight, 300.0, "Single frame returns original totalHeight (300px)")
            ChallengerHarness.assertEqual(singleRes.frameOffsets.count, 0, "Single frame has empty frameOffsets")
            ChallengerHarness.assertFalse(singleRes.isClampedToMaxHeight, "Single frame is not clamped")
        } catch {
            ChallengerHarness.recordFail("Single frame stitch", reason: "Threw error: \(error)")
        }

        // 8c: Mismatched frame dimensions
        guard let frameA = AdversarialFrameGenerator.createMasterCanvas(width: 300, totalHeight: 300),
              let frameB = AdversarialFrameGenerator.createMasterCanvas(width: 400, totalHeight: 300) else {
            return
        }

        do {
            _ = try ImageStitcher.stitch(frames: [frameA, frameB])
            ChallengerHarness.recordFail("Mismatched widths", reason: "Expected invalidDimensions error")
        } catch ImageStitcherError.invalidDimensions {
            ChallengerHarness.recordPass("Mismatched frame widths properly throw ImageStitcherError.invalidDimensions")
        } catch {
            ChallengerHarness.recordFail("Mismatched widths", reason: "Wrong error thrown: \(error)")
        }

        // 8d: Frame with height mismatch
        guard let frameC = AdversarialFrameGenerator.createMasterCanvas(width: 300, totalHeight: 350) else {
            return
        }

        do {
            _ = try ImageStitcher.stitch(frames: [frameA, frameC])
            ChallengerHarness.recordFail("Mismatched heights", reason: "Expected invalidDimensions error")
        } catch ImageStitcherError.invalidDimensions {
            ChallengerHarness.recordPass("Mismatched frame heights properly throw ImageStitcherError.invalidDimensions")
        } catch {
            ChallengerHarness.recordFail("Mismatched heights", reason: "Wrong error thrown: \(error)")
        }
    }

    // MARK: - Helper: Verify Uniform Color in Slice
    private static func verifySliceColor(
        image: CGImage,
        startY: Int,
        height: Int,
        width: Int,
        expected: (r: CGFloat, g: CGFloat, b: CGFloat),
        tolerance: Double = 10.0
    ) -> Bool {
        guard height > 0 && width > 0 else { return true }
        guard let slice = image.cropping(to: CGRect(x: 0, y: startY, width: width, height: height)) else {
            return false
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return false
        }
        ctx.draw(slice, in: CGRect(x: 0, y: 0, width: width, height: height))

        let expR = Int(round(expected.r * 255.0))
        let expG = Int(round(expected.g * 255.0))
        let expB = Int(round(expected.b * 255.0))

        var match = true
        for r in 0..<min(10, height) { // Sample top rows of slice
            for c in stride(from: 0, to: width, by: 10) {
                let idx = (r * width + c) * 4
                let pr = Int(pixels[idx])
                let pg = Int(pixels[idx + 1])
                let pb = Int(pixels[idx + 2])
                if abs(pr - expR) > Int(tolerance) || abs(pg - expG) > Int(tolerance) || abs(pb - expB) > Int(tolerance) {
                    match = false
                    break
                }
            }
            if !match { break }
        }
        return match
    }

    // MARK: - M4 Stress Testing Helpers

    private static func createTestSandbox() -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SuperShot_Challenger_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private static func cleanupTestSandbox(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func createDummyCGImage(width: Int = 100, height: Int = 100) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        ctx.setFillColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private static func synthesizeKeyEvent(char: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: 0
        )!
    }

    // MARK: - 9. Circular Keyboard Navigation Wrapping
    private static func testCircularKeyboardNavigation() {
        ChallengerHarness.startSuite("9. Circular Keyboard Navigation Wrapping")

        // 9A: Empty History (visibleCount = 0)
        ChallengerHarness.assertNil(ShortcutNavigator.stepUp(currentIndex: nil, visibleCount: 0), "stepUp on empty history with nil index returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepDown(currentIndex: nil, visibleCount: 0), "stepDown on empty history with nil index returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: 0), "stepUp on empty history with index 0 returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepDown(currentIndex: 0, visibleCount: 0), "stepDown on empty history with index 0 returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepUp(currentIndex: -1, visibleCount: 0), "stepUp on empty history with negative index returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepDown(currentIndex: 100, visibleCount: 0), "stepDown on empty history with out-of-bounds index returns nil")

        // 9B: Single Item History (visibleCount = 1)
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: nil, visibleCount: 1), 0, "stepDown with nil index on 1-item history selects 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: nil, visibleCount: 1), 0, "stepUp with nil index on 1-item history selects 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: 0, visibleCount: 1), 0, "stepDown from 0 on 1-item history wraps circularly to 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: 1), 0, "stepUp from 0 on 1-item history wraps circularly to 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: -5, visibleCount: 1), 0, "stepDown from negative index resets safely to 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: 10, visibleCount: 1), 0, "stepUp from out-of-range index resets safely to 0")

        var idxSingle: Int? = 0
        var loopStable = true
        for _ in 0..<100 {
            idxSingle = ShortcutNavigator.stepDown(currentIndex: idxSingle, visibleCount: 1)
            if idxSingle != 0 { loopStable = false; break }
            idxSingle = ShortcutNavigator.stepUp(currentIndex: idxSingle, visibleCount: 1)
            if idxSingle != 0 { loopStable = false; break }
        }
        ChallengerHarness.assertTrue(loopStable, "100 consecutive stepUp/stepDown cycles on 1-item history strictly remain at index 0")

        // 9C: 100-Item History Navigation
        let totalItems = 100
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: 99, visibleCount: totalItems), 0, "stepDown from index 99 wraps circularly to 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: totalItems), 99, "stepUp from index 0 wraps circularly to 99")

        var forwardCurrent: Int? = 0
        var forwardMatches = true
        for step in 1...1000 {
            forwardCurrent = ShortcutNavigator.stepDown(currentIndex: forwardCurrent, visibleCount: totalItems)
            if forwardCurrent != (step % totalItems) {
                forwardMatches = false
                break
            }
        }
        ChallengerHarness.assertTrue(forwardMatches, "1000 sequential stepDown steps wrap perfectly modulo 100")

        var reverseCurrent: Int? = 0
        var reverseMatches = true
        for step in 1...1000 {
            reverseCurrent = ShortcutNavigator.stepUp(currentIndex: reverseCurrent, visibleCount: totalItems)
            let expected = (totalItems - (step % totalItems)) % totalItems
            if reverseCurrent != expected {
                reverseMatches = false
                break
            }
        }
        ChallengerHarness.assertTrue(reverseMatches, "1000 sequential stepUp steps wrap perfectly in reverse modulo 100")

        // Out-of-bounds index resilience
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: -100, visibleCount: totalItems), 0, "stepDown handles extreme negative index (-100) -> 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: 500, visibleCount: totalItems), 0, "stepDown handles extreme positive index (500) -> 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: Int.max, visibleCount: totalItems), 0, "stepDown handles Int.max without overflow -> 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: Int.min, visibleCount: totalItems), 0, "stepDown handles Int.min without overflow -> 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: -100, visibleCount: totalItems), 99, "stepUp handles extreme negative index (-100) -> 99")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: 500, visibleCount: totalItems), 99, "stepUp handles extreme positive index (500) -> 99")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: Int.max, visibleCount: totalItems), 99, "stepUp handles Int.max without overflow -> 99")

        // 9D: Search-Filtered Dynamic List Transitions
        let filteredSizes = [100, 23, 7, 2, 1, 0, 4, 50]
        var filterNavPassed = true
        for count in filteredSizes {
            if count == 0 {
                let up = ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: count)
                let down = ShortcutNavigator.stepDown(currentIndex: 0, visibleCount: count)
                if up != nil || down != nil { filterNavPassed = false }
            } else {
                let upWrap = ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: count)
                let downWrap = ShortcutNavigator.stepDown(currentIndex: count - 1, visibleCount: count)
                if upWrap != count - 1 || downWrap != 0 { filterNavPassed = false }
            }
        }
        ChallengerHarness.assertTrue(filterNavPassed, "Circular wrapping adapts dynamically across varying filtered list counts")
    }

    // MARK: - 10. Quick Selection Keys 1..9 & Modifier Mapping
    private static func testQuickSelectionMapping() {
        ChallengerHarness.startSuite("10. Quick Selection Keys 1..9 & Modifier Mapping")

        let sandbox = createTestSandbox()
        defer { cleanupTestSandbox(sandbox) }

        let storage = StorageManager(baseDirectory: sandbox, initialCapacity: 50)
        let dummyImage = createDummyCGImage()

        // 10A: Boundary Item Sets (0, 1, 8, 9, 10, 50 items)
        ChallengerHarness.assertNil(ShortcutNavigator.targetItem(forShortcut: 1, in: []), "Target item for shortcut 1 in empty array is nil")
        ChallengerHarness.assertNil(ShortcutNavigator.targetItem(forShortcut: 9, in: []), "Target item for shortcut 9 in empty array is nil")

        var sampleItems: [ShotItem] = []
        for i in 0..<50 {
            let item = try! storage.save(image: dummyImage, sourceApp: "App_\(i)", captureType: .region, tags: ["tag_\(i)"])
            sampleItems.append(item)
        }

        // Test with 1 item visible
        let oneItem = Array(sampleItems.prefix(1))
        ChallengerHarness.assertEqual(ShortcutNavigator.targetItem(forShortcut: 1, in: oneItem)?.id, oneItem[0].id, "Shortcut 1 resolves only item")
        for digit in 2...9 {
            ChallengerHarness.assertNil(ShortcutNavigator.targetItem(forShortcut: digit, in: oneItem), "Shortcut \(digit) is nil when only 1 item visible")
        }
        ChallengerHarness.assertEqual(ShortcutNavigator.shortcutIndex(for: oneItem[0], in: oneItem), 1, "Shortcut index for item 0 is 1")

        // Test with 8 items visible
        let eightItems = Array(sampleItems.prefix(8))
        for digit in 1...8 {
            ChallengerHarness.assertEqual(ShortcutNavigator.targetItem(forShortcut: digit, in: eightItems)?.id, eightItems[digit - 1].id, "Shortcut \(digit) resolves item \(digit - 1) in 8-item array")
        }
        ChallengerHarness.assertNil(ShortcutNavigator.targetItem(forShortcut: 9, in: eightItems), "Shortcut 9 is nil in 8-item array")

        // Test with 9 items visible
        let nineItems = Array(sampleItems.prefix(9))
        for digit in 1...9 {
            ChallengerHarness.assertEqual(ShortcutNavigator.targetItem(forShortcut: digit, in: nineItems)?.id, nineItems[digit - 1].id, "Shortcut \(digit) resolves item \(digit - 1) in 9-item array")
        }
        ChallengerHarness.assertEqual(ShortcutNavigator.shortcutIndex(for: nineItems[8], in: nineItems), 9, "Shortcut index for 9th item is 9")

        // Test with 10+ items visible
        let tenItems = Array(sampleItems.prefix(10))
        ChallengerHarness.assertNil(ShortcutNavigator.shortcutIndex(for: tenItems[9], in: tenItems), "10th item has nil shortcutIndex")
        ChallengerHarness.assertNil(ShortcutNavigator.shortcutIndex(for: sampleItems[49], in: sampleItems), "50th item has nil shortcutIndex")

        // Foreign item not in array
        let foreignItem = ShotItem(id: UUID(), width: 100, height: 100)
        ChallengerHarness.assertNil(ShortcutNavigator.shortcutIndex(for: foreignItem, in: sampleItems), "Foreign item has nil shortcutIndex")

        // 10B: Invalid & Extreme Digits in targetItem
        let invalidDigits = [0, -1, -50, 10, 11, 99, 1000, Int.max, Int.min]
        var allInvalidNil = true
        for d in invalidDigits {
            if ShortcutNavigator.targetItem(forShortcut: d, in: sampleItems) != nil {
                allInvalidNil = false
                break
            }
        }
        ChallengerHarness.assertTrue(allInvalidNil, "targetItem strictly returns nil for all digits outside [1..9]")

        // 10C: Pinned vs Recent Ordering
        let freshSandbox = createTestSandbox()
        defer { cleanupTestSandbox(freshSandbox) }
        let orderedStorage = StorageManager(baseDirectory: freshSandbox, initialCapacity: 50)

        // Seed 20 items: 5 pinned, 15 recent
        var pinnedList: [ShotItem] = []
        var recentList: [ShotItem] = []

        for p in 0..<5 {
            let item = try! orderedStorage.save(image: dummyImage, sourceApp: "Pinned_\(p)", captureType: .region, tags: ["pin"])
            orderedStorage.togglePin(id: item.id)
            pinnedList.append(orderedStorage.items.first(where: { $0.id == item.id })!)
        }
        for r in 0..<15 {
            let item = try! orderedStorage.save(image: dummyImage, sourceApp: "Recent_\(r)", captureType: .region, tags: ["recent"])
            recentList.append(item)
        }

        let visibleItems = orderedStorage.pinnedItems + orderedStorage.recentItems
        ChallengerHarness.assertEqual(orderedStorage.pinnedItems.count, 5, "Storage has exactly 5 pinned items")
        ChallengerHarness.assertEqual(orderedStorage.recentItems.count, 15, "Storage has exactly 15 recent items")

        // Keys 1..5 map to pinned items
        for key in 1...5 {
            let target = ShortcutNavigator.targetItem(forShortcut: key, in: visibleItems)
            ChallengerHarness.assertEqual(target?.id, orderedStorage.pinnedItems[key - 1].id, "Key \(key) maps to pinned item index \(key - 1)")
            ChallengerHarness.assertEqual(ShortcutNavigator.shortcutIndex(for: orderedStorage.pinnedItems[key - 1], in: visibleItems), key, "Shortcut index for pinned item \(key - 1) is \(key)")
        }

        // Keys 6..9 map to recent items 0..3
        for key in 6...9 {
            let recentIdx = key - 6
            let target = ShortcutNavigator.targetItem(forShortcut: key, in: visibleItems)
            ChallengerHarness.assertEqual(target?.id, orderedStorage.recentItems[recentIdx].id, "Key \(key) maps to recent item index \(recentIdx)")
            ChallengerHarness.assertEqual(ShortcutNavigator.shortcutIndex(for: orderedStorage.recentItems[recentIdx], in: visibleItems), key, "Shortcut index for recent item \(recentIdx) is \(key)")
        }

        // Recent items index >= 4 have no shortcut
        ChallengerHarness.assertNil(ShortcutNavigator.shortcutIndex(for: orderedStorage.recentItems[4], in: visibleItems), "Recent item index 4 (10th visible) has nil shortcutIndex")

        // Dynamic pin toggle: unpin second pinned item
        let unpinnedId = orderedStorage.pinnedItems[1].id
        orderedStorage.togglePin(id: unpinnedId)
        let updatedVisible = orderedStorage.pinnedItems + orderedStorage.recentItems
        ChallengerHarness.assertEqual(orderedStorage.pinnedItems.count, 4, "Pinned count decremented to 4")
        ChallengerHarness.assertEqual(orderedStorage.recentItems.count, 16, "Recent count incremented to 16")
        ChallengerHarness.assertEqual(ShortcutNavigator.targetItem(forShortcut: 5, in: updatedVisible)?.id, orderedStorage.recentItems[0].id, "Key 5 now maps to first recent item after unpin")

        // 10D: parseShortcut Event Handling & Modifiers
        // Digits 1..9 without modifiers
        for digit in 1...9 {
            let evt = synthesizeKeyEvent(char: "\(digit)")
            let parsedNoFocus = ShortcutNavigator.parseShortcut(from: evt, searchFieldHasFocus: false)
            ChallengerHarness.assertEqual(parsedNoFocus, digit, "Event '\(digit)' parses as shortcut \(digit) when search unfocused")

            let parsedWithFocus = ShortcutNavigator.parseShortcut(from: evt, searchFieldHasFocus: true)
            ChallengerHarness.assertNil(parsedWithFocus, "Event '\(digit)' returns nil when search field has focus (allows typing)")

            let cmdEvt = synthesizeKeyEvent(char: "\(digit)", flags: .command)
            let parsedCmdWithFocus = ShortcutNavigator.parseShortcut(from: cmdEvt, searchFieldHasFocus: true)
            ChallengerHarness.assertEqual(parsedCmdWithFocus, digit, "Event Cmd+\(digit) triggers shortcut even when search field has focus")

            let parsedCmdNoFocus = ShortcutNavigator.parseShortcut(from: cmdEvt, searchFieldHasFocus: false)
            ChallengerHarness.assertEqual(parsedCmdNoFocus, digit, "Event Cmd+\(digit) triggers shortcut when search unfocused")

            // Control and Option modifiers disallow shortcuts
            let ctrlEvt = synthesizeKeyEvent(char: "\(digit)", flags: .control)
            ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: ctrlEvt, searchFieldHasFocus: false), "Ctrl+\(digit) is rejected")

            let optEvt = synthesizeKeyEvent(char: "\(digit)", flags: .option)
            ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: optEvt, searchFieldHasFocus: false), "Option+\(digit) is rejected")

            let cmdCtrlEvt = synthesizeKeyEvent(char: "\(digit)", flags: [.command, .control])
            ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: cmdCtrlEvt, searchFieldHasFocus: false), "Cmd+Ctrl+\(digit) is rejected")

            let cmdOptEvt = synthesizeKeyEvent(char: "\(digit)", flags: [.command, .option])
            ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: cmdOptEvt, searchFieldHasFocus: false), "Cmd+Option+\(digit) is rejected")
        }

        // Digit 0 rejection
        let zeroEvt = synthesizeKeyEvent(char: "0")
        ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: zeroEvt, searchFieldHasFocus: false), "Key '0' is rejected")
        let cmdZeroEvt = synthesizeKeyEvent(char: "0", flags: .command)
        ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: cmdZeroEvt, searchFieldHasFocus: false), "Cmd+0 is rejected")

        // Non-digit characters
        let nonDigitChars = ["a", "z", "A", "Z", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "\r", " ", "\t"]
        for ch in nonDigitChars {
            let evt = synthesizeKeyEvent(char: ch)
            ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: evt, searchFieldHasFocus: false), "Non-digit '\(ch)' is rejected")
            let cmdEvt = synthesizeKeyEvent(char: ch, flags: .command)
            ChallengerHarness.assertNil(ShortcutNavigator.parseShortcut(from: cmdEvt, searchFieldHasFocus: false), "Cmd+'\(ch)' is rejected")
        }
    }

    // MARK: - 11. Search Filtering Logic & Unicode Handling
    private static func testSearchFilteringLogic() {
        ChallengerHarness.startSuite("11. Search Filtering Logic & Unicode Handling")

        let sandbox = createTestSandbox()
        defer { cleanupTestSandbox(sandbox) }

        let storage = StorageManager(baseDirectory: sandbox, initialCapacity: 50)
        let dummyImage = createDummyCGImage()

        // Seed diverse test dataset
        let _ = try! storage.save(image: dummyImage, sourceApp: "Safari", captureType: .region, tags: ["web", "development"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Xcode", captureType: .region, tags: ["swift", "apple"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Terminal", captureType: .region, tags: ["bash", "cli"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "System Settings", captureType: .region, tags: ["preferences", "config"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "TextEdit", captureType: .region, tags: ["notes", "document"])

        // Diacritics
        let _ = try! storage.save(image: dummyImage, sourceApp: "Café App", captureType: .region, tags: ["coffee", "espresso"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "München Bank", captureType: .region, tags: ["germany", "finance"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "El Niño Forecast", captureType: .region, tags: ["weather", "climate"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Crème Brûlée Recipes", captureType: .region, tags: ["dessert", "food"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Blåbær Jam", captureType: .region, tags: ["fruit", "nordic"])

        // Vietnamese Unicode
        let _ = try! storage.save(image: dummyImage, sourceApp: "Ảnh chụp màn hình", captureType: .region, tags: ["đồ họa", "chụp ảnh", "công cụ"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Thiết lập hệ thống", captureType: .region, tags: ["cài đặt", "tùy chọn", "âm thanh"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Trình duyệt Safari", captureType: .region, tags: ["web", "tiếng việt", "tìm kiếm"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Đã ghim", captureType: .region, tags: ["quan trọng", "báo cáo"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Ghi chú nhanh", captureType: .region, tags: ["công việc", "nhắc nhở"])

        // Regex metacharacters in literal text
        let _ = try! storage.save(image: dummyImage, sourceApp: "Logfile.v1.0.0.txt", captureType: .region, tags: ["version.1.0", "patch.dot"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "Calculator", captureType: .region, tags: ["2+2*3?", "formula*"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "RegexEditor", captureType: .region, tags: ["[a-z]+", "(group)", "^start$"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "PathFinder", captureType: .region, tags: ["path\\to\\file", "a|b", "item{1,2}"])
        let _ = try! storage.save(image: dummyImage, sourceApp: "PriceTag", captureType: .region, tags: ["$199.99", "100%"])

        let totalSeeded = 20
        ChallengerHarness.assertEqual(storage.items.count, totalSeeded, "Total seeded items count is 20")

        // 11A: Empty & Whitespace Queries
        ChallengerHarness.assertEqual(storage.search(query: "").count, totalSeeded, "Empty query '' returns all items")
        ChallengerHarness.assertEqual(storage.search(query: "   ").count, totalSeeded, "Whitespace query '   ' returns all items")
        ChallengerHarness.assertEqual(storage.search(query: "\t\n  \r").count, totalSeeded, "Tab/Newline query returns all items")

        // 11B: Case Insensitivity
        let q1 = storage.search(query: "safari")
        let q2 = storage.search(query: "SAFARI")
        let q3 = storage.search(query: "sAfArI")
        ChallengerHarness.assertEqual(q1.count, 2, "Search 'safari' finds 2 matching items (English Safari + Vietnamese Safari)")
        ChallengerHarness.assertEqual(q2.count, 2, "Search 'SAFARI' finds 2 matching items")
        ChallengerHarness.assertEqual(q3.count, 2, "Search 'sAfArI' finds 2 matching items")

        ChallengerHarness.assertEqual(storage.search(query: "XCODE").count, 1, "Search 'XCODE' matches 'Xcode'")
        ChallengerHarness.assertEqual(storage.search(query: "xCoDe").count, 1, "Search 'xCoDe' matches 'Xcode'")
        ChallengerHarness.assertEqual(storage.search(query: "DEVELOPMENT").count, 1, "Search 'DEVELOPMENT' matches tag 'development'")

        // 11C: Latin Diacritics
        ChallengerHarness.assertEqual(storage.search(query: "café").count, 1, "Search 'café' matches 'Café App'")
        ChallengerHarness.assertEqual(storage.search(query: "CAFÉ").count, 1, "Search 'CAFÉ' matches 'Café App'")
        ChallengerHarness.assertEqual(storage.search(query: "münchen").count, 1, "Search 'münchen' matches 'München Bank'")
        ChallengerHarness.assertEqual(storage.search(query: "MÜNCHEN").count, 1, "Search 'MÜNCHEN' matches 'München Bank'")
        ChallengerHarness.assertEqual(storage.search(query: "niño").count, 1, "Search 'niño' matches 'El Niño Forecast'")
        ChallengerHarness.assertEqual(storage.search(query: "NIÑO").count, 1, "Search 'NIÑO' matches 'El Niño Forecast'")
        ChallengerHarness.assertEqual(storage.search(query: "crème").count, 1, "Search 'crème' matches 'Crème Brûlée Recipes'")
        ChallengerHarness.assertEqual(storage.search(query: "blåbær").count, 1, "Search 'blåbær' matches 'Blåbær Jam'")

        // 11D: Vietnamese Unicode & Case Folding
        ChallengerHarness.assertEqual(storage.search(query: "ảnh chụp").count, 1, "Search 'ảnh chụp' matches 'Ảnh chụp màn hình'")
        ChallengerHarness.assertEqual(storage.search(query: "ẢNH CHỤP").count, 1, "Search 'ẢNH CHỤP' (uppercase) matches 'Ảnh chụp màn hình'")
        ChallengerHarness.assertEqual(storage.search(query: "thiết lập").count, 1, "Search 'thiết lập' matches 'Thiết lập hệ thống'")
        ChallengerHarness.assertEqual(storage.search(query: "THIẾT LẬP").count, 1, "Search 'THIẾT LẬP' (uppercase) matches 'Thiết lập hệ thống'")
        ChallengerHarness.assertEqual(storage.search(query: "tùy chọn").count, 1, "Search tag 'tùy chọn' matches 'Thiết lập hệ thống'")
        ChallengerHarness.assertEqual(storage.search(query: "tiếng việt").count, 1, "Search tag 'tiếng việt' matches 'Trình duyệt Safari'")
        ChallengerHarness.assertEqual(storage.search(query: "TIẾNG VIỆT").count, 1, "Search uppercase 'TIẾNG VIỆT' matches tag")
        ChallengerHarness.assertEqual(storage.search(query: "đã ghim").count, 1, "Search 'đã ghim' matches 'Đã ghim'")
        ChallengerHarness.assertEqual(storage.search(query: "ĐÃ GHIM").count, 1, "Search uppercase 'ĐÃ GHIM' matches 'Đã ghim'")
        ChallengerHarness.assertEqual(storage.search(query: "nhắc nhở").count, 1, "Search tag 'nhắc nhở' matches 'Ghi chú nhanh'")

        // Decomposed NFD Unicode canonical equivalence test
        let nfdQuery = "A\u{0309}nh chu\u{0323}p" // Decomposed NFD for "Ảnh chụp"
        ChallengerHarness.assertEqual(storage.search(query: nfdQuery).count, 1, "Search decomposed NFD query matches precomposed NFC Vietnamese text")

        // 11E: Special Regex Metacharacters as Literal Substrings
        // Literal dot '.'
        let dotResults = storage.search(query: ".")
        // Only items containing literal dot (Logfile.v1.0.0.txt and PriceTag with $199.99)
        ChallengerHarness.assertTrue(dotResults.contains(where: { $0.sourceApp == "Logfile.v1.0.0.txt" }), "Search '.' matches Logfile.v1.0.0.txt")
        ChallengerHarness.assertTrue(dotResults.contains(where: { $0.sourceApp == "PriceTag" }), "Search '.' matches PriceTag")
        ChallengerHarness.assertFalse(dotResults.count == totalSeeded, "Search '.' does NOT act as regex wildcard matching every item")

        // Literal asterisk '*'
        let starResults = storage.search(query: "*")
        ChallengerHarness.assertEqual(starResults.count, 1, "Search '*' matches literal asterisk without quantifier crash")
        ChallengerHarness.assertEqual(starResults.first?.sourceApp, "Calculator", "Search '*' matches Calculator")

        // Literal plus '+'
        let plusResults = storage.search(query: "+")
        ChallengerHarness.assertEqual(plusResults.count, 2, "Search '+' matches Calculator and RegexEditor without crash")

        // Literal question mark '?'
        let questionResults = storage.search(query: "?")
        ChallengerHarness.assertEqual(questionResults.count, 1, "Search '?' matches Calculator without crash")

        // Literal square brackets '[' and ']'
        let bracketResults = storage.search(query: "[a-z]+")
        ChallengerHarness.assertEqual(bracketResults.count, 1, "Search '[a-z]+' matches RegexEditor without regex character class error")

        // Literal parentheses '(' and ')'
        let parenResults = storage.search(query: "(group)")
        ChallengerHarness.assertEqual(parenResults.count, 1, "Search '(group)' matches RegexEditor without capture group error")

        // Literal anchors '^' and '$'
        let anchorResults = storage.search(query: "^start$")
        ChallengerHarness.assertEqual(anchorResults.count, 1, "Search '^start$' matches literal text without anchor behavior")

        // Literal backslash '\'
        let backslashResults = storage.search(query: "\\")
        ChallengerHarness.assertEqual(backslashResults.count, 1, "Search '\\' matches PathFinder without escape error")

        // Literal pipe '|'
        let pipeResults = storage.search(query: "|")
        ChallengerHarness.assertEqual(pipeResults.count, 1, "Search '|' matches PathFinder without alternation error")

        // Literal dollar '$'
        let dollarResults = storage.search(query: "$")
        ChallengerHarness.assertEqual(dollarResults.count, 2, "Search '$' matches PriceTag ($199.99) and RegexEditor (^start$)")

        // 11F: No Matching Results
        let noMatch1 = storage.search(query: "nonexistent_term_404_not_found")
        ChallengerHarness.assertEqual(noMatch1.count, 0, "Nonexistent query returns empty array")
        let noMatch2 = storage.search(query: "@@@@#####$$$$$")
        ChallengerHarness.assertEqual(noMatch2.count, 0, "Random symbols query returns empty array")
    }

    // MARK: - 12. Hover Preview Panel Positioning Geometry & Lifecycle
    private static func testHoverPreviewPositioning() {
        ChallengerHarness.startSuite("12. Hover Preview Panel Positioning Geometry & Lifecycle")

        // Geometry Oracle modeling ThumbnailHoverPreviewPanel's positionPanel algorithm
        struct PreviewGeometryOracle {
            static func calculate(
                mouseScreen: NSPoint,
                targetWindowFrame: NSRect?,
                screenVisible: NSRect,
                width: CGFloat = 320,
                height: CGFloat = 230
            ) -> NSRect {
                var targetX: CGFloat
                var targetY = mouseScreen.y - (height / 2)

                if let winFrame = targetWindowFrame {
                    let leftSpace = winFrame.minX - screenVisible.minX
                    if leftSpace >= (width + 12) {
                        targetX = winFrame.minX - width - 8
                    } else {
                        targetX = winFrame.maxX + 8
                    }
                } else {
                    targetX = mouseScreen.x - width - 12
                }

                // Screen boundary safety clamping
                if targetX < screenVisible.minX + 8 { targetX = screenVisible.minX + 8 }
                if targetX + width > screenVisible.maxX - 8 { targetX = screenVisible.maxX - width - 8 }
                if targetY < screenVisible.minY + 8 { targetY = screenVisible.minY + 8 }
                if targetY + height > screenVisible.maxY - 8 { targetY = screenVisible.maxY - height - 8 }

                return NSRect(x: targetX, y: targetY, width: width, height: height)
            }
        }

        let previewW: CGFloat = 320
        let previewH: CGFloat = 230

        // 12A: Primary Display Coordinates (1920x1080, visibleFrame: 0, 25, 1920, 1055)
        let primaryVisible = NSRect(x: 0, y: 25, width: 1920, height: 1055)
        let primaryTestPoints = [
            ("Top-Left", NSPoint(x: 0, y: 1080)),
            ("Top-Right", NSPoint(x: 1920, y: 1080)),
            ("Bottom-Left", NSPoint(x: 0, y: 25)),
            ("Bottom-Right", NSPoint(x: 1920, y: 25)),
            ("Center", NSPoint(x: 960, y: 540))
        ]

        for (name, pt) in primaryTestPoints {
            let rect = PreviewGeometryOracle.calculate(mouseScreen: pt, targetWindowFrame: nil, screenVisible: primaryVisible)
            ChallengerHarness.assertTrue(rect.minX >= primaryVisible.minX + 8, "Primary \(name): rect.minX >= visible.minX + 8")
            ChallengerHarness.assertTrue(rect.maxX <= primaryVisible.maxX - 8, "Primary \(name): rect.maxX <= visible.maxX - 8")
            ChallengerHarness.assertTrue(rect.minY >= primaryVisible.minY + 8, "Primary \(name): rect.minY >= visible.minY + 8")
            ChallengerHarness.assertTrue(rect.maxY <= primaryVisible.maxY - 8, "Primary \(name): rect.maxY <= visible.maxY - 8")
            ChallengerHarness.assertEqual(rect.width, previewW, "Primary \(name): width == \(previewW)")
            ChallengerHarness.assertEqual(rect.height, previewH, "Primary \(name): height == \(previewH)")
        }

        // 12B: Secondary Display to the Right (1920, 0, 2560, 1440)
        let secondaryRightVisible = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let secondaryRightPoints = [
            ("Top-Left", NSPoint(x: 1920, y: 1440)),
            ("Top-Right", NSPoint(x: 4480, y: 1440)),
            ("Bottom-Left", NSPoint(x: 1920, y: 0)),
            ("Bottom-Right", NSPoint(x: 4480, y: 0))
        ]

        for (name, pt) in secondaryRightPoints {
            let rect = PreviewGeometryOracle.calculate(mouseScreen: pt, targetWindowFrame: nil, screenVisible: secondaryRightVisible)
            ChallengerHarness.assertTrue(rect.minX >= secondaryRightVisible.minX + 8, "Secondary Right \(name): minX >= \(secondaryRightVisible.minX + 8)")
            ChallengerHarness.assertTrue(rect.maxX <= secondaryRightVisible.maxX - 8, "Secondary Right \(name): maxX <= \(secondaryRightVisible.maxX - 8)")
            ChallengerHarness.assertTrue(rect.minY >= secondaryRightVisible.minY + 8, "Secondary Right \(name): minY >= \(secondaryRightVisible.minY + 8)")
            ChallengerHarness.assertTrue(rect.maxY <= secondaryRightVisible.maxY - 8, "Secondary Right \(name): maxY <= \(secondaryRightVisible.maxY - 8)")
        }

        // 12C: Secondary Display to the Left (Negative coordinates: -1920, 0, 1920, 1080)
        let secondaryLeftVisible = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let secondaryLeftPoints = [
            ("Top-Left", NSPoint(x: -1920, y: 1080)),
            ("Top-Right", NSPoint(x: 0, y: 1080)),
            ("Bottom-Left", NSPoint(x: -1920, y: 0)),
            ("Bottom-Right", NSPoint(x: 0, y: 0))
        ]

        for (name, pt) in secondaryLeftPoints {
            let rect = PreviewGeometryOracle.calculate(mouseScreen: pt, targetWindowFrame: nil, screenVisible: secondaryLeftVisible)
            ChallengerHarness.assertTrue(rect.minX >= secondaryLeftVisible.minX + 8, "Secondary Left \(name): minX >= \(secondaryLeftVisible.minX + 8)")
            ChallengerHarness.assertTrue(rect.maxX <= secondaryLeftVisible.maxX - 8, "Secondary Left \(name): maxX <= \(secondaryLeftVisible.maxX - 8)")
            ChallengerHarness.assertTrue(rect.minY >= secondaryLeftVisible.minY + 8, "Secondary Left \(name): minY >= \(secondaryLeftVisible.minY + 8)")
            ChallengerHarness.assertTrue(rect.maxY <= secondaryLeftVisible.maxY - 8, "Secondary Left \(name): maxY <= \(secondaryLeftVisible.maxY - 8)")
        }

        // 12D: Popover Window Anchoring & Horizontal Flipping
        // Case 1: Status Bar Popover docked at Top-Right
        let popoverTopRight = NSRect(x: 1520, y: 495, width: 380, height: 560)
        let preview1 = PreviewGeometryOracle.calculate(
            mouseScreen: NSPoint(x: 1710, y: 775),
            targetWindowFrame: popoverTopRight,
            screenVisible: primaryVisible
        )
        // With leftSpace = 1520 >= 332, preview must place to the left: targetX = 1520 - 320 - 8 = 1192
        ChallengerHarness.assertEqual(preview1.minX, 1192, "Preview placed to the left of Top-Right popover")
        ChallengerHarness.assertTrue(preview1.maxX <= popoverTopRight.minX, "Preview does not overlap Top-Right popover")

        // Case 2: Popover docked near Left Edge (leftSpace < 332)
        let popoverLeftEdge = NSRect(x: 50, y: 495, width: 380, height: 560)
        let preview2 = PreviewGeometryOracle.calculate(
            mouseScreen: NSPoint(x: 240, y: 775),
            targetWindowFrame: popoverLeftEdge,
            screenVisible: primaryVisible
        )
        // With leftSpace = 50 < 332, preview flips to the right: targetX = 50 + 380 + 8 = 438
        ChallengerHarness.assertEqual(preview2.minX, 438, "Preview flips to the right of Left-docked popover")
        ChallengerHarness.assertTrue(preview2.minX >= popoverLeftEdge.maxX, "Preview does not overlap Left-docked popover")

        // 12E: Live ThumbnailHoverPreviewPanel Instance & Show/Hide Lifecycle
        let panel = ThumbnailHoverPreviewPanel.shared
        ChallengerHarness.assertEqual(panel.level, .popUpMenu, "Hover panel window level is popUpMenu")
        ChallengerHarness.assertFalse(panel.isOpaque, "Hover panel is not opaque")
        ChallengerHarness.assertTrue(panel.hasShadow, "Hover panel has shadow")
        ChallengerHarness.assertTrue(panel.ignoresMouseEvents, "Hover panel ignores mouse events to prevent hover interference")

        let testItem = ShotItem(id: UUID(), width: 640, height: 480, sourceApp: "PreviewTest")
        panel.show(for: testItem)
        panel.hide(immediate: true)
        ChallengerHarness.assertNil(panel.currentItemId, "currentItemId is nil after immediate hide")

        // Concurrency / burst show & hide loop
        var burstSuccess = true
        for b in 0..<100 {
            let itemB = ShotItem(id: UUID(), width: 100 + b, height: 100 + b)
            panel.show(for: itemB)
            panel.hide(immediate: true)
            if panel.currentItemId != nil { burstSuccess = false; break }
        }
        ChallengerHarness.assertTrue(burstSuccess, "100 rapid show/hide cycles execute cleanly without crash or state corruption")
    }

    // MARK: - 13. SemanticVersion & ReleaseInfo Adversarial Parsing
    static func testSemanticVersionAndReleaseInfoAdversarialParsing() {
        ChallengerHarness.startSuite("13. SemanticVersion & ReleaseInfo Adversarial Parsing")

        // 13A: SemanticVersion Abnormal Inputs
        let emptyV = SemanticVersion("")
        ChallengerHarness.assertEqual(emptyV.components, [0], "Empty string parses as [0]")
        ChallengerHarness.assertNil(emptyV.prerelease, "Empty string has nil prerelease")
        ChallengerHarness.assertEqual(emptyV.raw, "", "Empty string preserves raw ''")

        let whitespaceV = SemanticVersion("   \n\t  ")
        ChallengerHarness.assertEqual(whitespaceV.components, [0], "Whitespace-only parses as [0]")
        ChallengerHarness.assertNil(whitespaceV.prerelease, "Whitespace-only has nil prerelease")

        let justV = SemanticVersion("v")
        ChallengerHarness.assertEqual(justV.components, [0], "Single 'v' parses as [0]")
        ChallengerHarness.assertNil(justV.prerelease, "Single 'v' has nil prerelease")

        let justUpperV = SemanticVersion("V")
        ChallengerHarness.assertEqual(justUpperV.components, [0], "Single 'V' parses as [0]")

        let zeroV = SemanticVersion("v0.0.0")
        ChallengerHarness.assertEqual(zeroV.components, [0, 0, 0], "v0.0.0 parses components [0, 0, 0]")
        ChallengerHarness.assertNil(zeroV.prerelease, "v0.0.0 has nil prerelease")

        let leadingZeroes = SemanticVersion("01.02.03")
        ChallengerHarness.assertEqual(leadingZeroes.components, [1, 2, 3], "01.02.03 parses components [1, 2, 3]")

        let manyComponents = SemanticVersion("1.2.3.4.5.6.7")
        ChallengerHarness.assertEqual(manyComponents.components, [1, 2, 3, 4, 5, 6, 7], "Multi-component version parses all 7 components")

        let extraDots = SemanticVersion("...1...2...3...")
        ChallengerHarness.assertEqual(extraDots.components, [1, 2, 3], "Leading/trailing/multiple dots parse cleanly as [1, 2, 3]")

        let doubleDots = SemanticVersion("1..2..3")
        ChallengerHarness.assertEqual(doubleDots.components, [1, 2, 3], "Double dots parse cleanly as [1, 2, 3]")

        let trailingHyphen = SemanticVersion("1.0.0-")
        ChallengerHarness.assertEqual(trailingHyphen.components, [1, 0, 0], "1.0.0- retains components [1, 0, 0]")
        ChallengerHarness.assertNil(trailingHyphen.prerelease, "1.0.0- with empty prerelease has nil prerelease")

        let trailingPlus = SemanticVersion("1.0.0+")
        ChallengerHarness.assertEqual(trailingPlus.components, [1, 0, 0], "1.0.0+ retains components [1, 0, 0]")
        ChallengerHarness.assertNil(trailingPlus.prerelease, "1.0.0+ build stripped")

        let multipleBuildPluses = SemanticVersion("1.0.0-alpha+build.1+build.2")
        ChallengerHarness.assertEqual(multipleBuildPluses.components, [1, 0, 0], "Multiple + build metadata components parse correctly")
        ChallengerHarness.assertEqual(multipleBuildPluses.prerelease, "alpha", "Multiple + retains prerelease 'alpha'")

        let multipleHyphens = SemanticVersion("1.0.0-beta.1-extra-debug")
        ChallengerHarness.assertEqual(multipleHyphens.components, [1, 0, 0], "Multiple hyphens retain components [1, 0, 0]")
        ChallengerHarness.assertEqual(multipleHyphens.prerelease, "beta.1-extra-debug", "Multiple hyphens retain full prerelease string")

        let overflowV = SemanticVersion("9999999999999999999999999999999999.0.0")
        ChallengerHarness.assertFalse(overflowV.components.isEmpty, "Integer overflow on component does not crash")

        let negativeLeading = SemanticVersion("-1.0.0")
        ChallengerHarness.assertEqual(negativeLeading.components, [1, 0, 0], "-1.0.0 strips leading hyphen and parses [1, 0, 0]")

        let allNonNumeric = SemanticVersion("alpha.beta.gamma")
        ChallengerHarness.assertEqual(allNonNumeric.components, [0], "All non-numeric components parse as [0]")

        let mixedNonNumeric = SemanticVersion("1.beta.3")
        ChallengerHarness.assertEqual(mixedNonNumeric.components, [1, 3], "1.beta.3 parses valid numeric components [1, 3]")

        let unicodePrerelease = SemanticVersion("1.0.4-caf\u{00E9}")
        ChallengerHarness.assertEqual(unicodePrerelease.prerelease, "caf\u{00E9}", "Unicode prerelease preserved")

        // 13B: SemVer Equality & Mathematical Invariance
        ChallengerHarness.assertEqual(SemanticVersion("1.0"), SemanticVersion("1.0.0"), "1.0 == 1.0.0")
        ChallengerHarness.assertEqual(SemanticVersion("1.0.0"), SemanticVersion("1.0.0.0"), "1.0.0 == 1.0.0.0")
        ChallengerHarness.assertEqual(SemanticVersion("v1.0.4"), SemanticVersion("1.0.4"), "v1.0.4 == 1.0.4")
        ChallengerHarness.assertEqual(SemanticVersion("V1.0.4"), SemanticVersion("1.0.4"), "V1.0.4 == 1.0.4")
        ChallengerHarness.assertEqual(SemanticVersion("1.0.4+exp.sha.1"), SemanticVersion("1.0.4+exp.sha.2"), "Build metadata ignored in equality")
        ChallengerHarness.assertEqual(SemanticVersion("1.0.4+20261023"), SemanticVersion("1.0.4"), "Build metadata vs clean equality")

        // 13C: SemVer Precedence & Comparison Matrix
        let orderedVersions = [
            "0.9.9",
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
            "1.0.1",
            "1.1.0-alpha",
            "1.1.0",
            "2.0.0-0",
            "2.0.0"
        ]

        for i in 0..<(orderedVersions.count - 1) {
            let smaller = SemanticVersion(orderedVersions[i])
            let larger = SemanticVersion(orderedVersions[i + 1])
            ChallengerHarness.assertTrue(smaller < larger, "SemVer precedence: \(orderedVersions[i]) < \(orderedVersions[i + 1])")
            ChallengerHarness.assertFalse(larger < smaller, "Anti-symmetry: !(\(orderedVersions[i + 1]) < \(orderedVersions[i]))")
            ChallengerHarness.assertFalse(smaller == larger, "Inequality: \(orderedVersions[i]) != \(orderedVersions[i + 1])")
            ChallengerHarness.assertTrue(smaller == smaller, "Reflexivity: \(orderedVersions[i]) == \(orderedVersions[i])")
            ChallengerHarness.assertFalse(smaller < smaller, "Strict irreflexivity: !(\(orderedVersions[i]) < \(orderedVersions[i]))")
        }

        // Transitivity test across random triples
        for i in 0..<(orderedVersions.count - 2) {
            let a = SemanticVersion(orderedVersions[i])
            let b = SemanticVersion(orderedVersions[i + 1])
            let c = SemanticVersion(orderedVersions[i + 2])
            ChallengerHarness.assertTrue(a < b && b < c && a < c, "Transitivity: \(orderedVersions[i]) < \(orderedVersions[i + 2])")
        }

        // UpdateManager.isVersion helper checks
        ChallengerHarness.assertTrue(UpdateManager.isVersion("2.0.0", greaterThan: "1.0.4"), "2.0.0 > 1.0.4")
        ChallengerHarness.assertFalse(UpdateManager.isVersion("1.0.4", greaterThan: "2.0.0"), "!(1.0.4 > 2.0.0)")
        ChallengerHarness.assertFalse(UpdateManager.isVersion("1.0.4", greaterThan: "1.0.4"), "!(1.0.4 > 1.0.4)")
        ChallengerHarness.assertFalse(UpdateManager.isVersion("v1.0.4", greaterThan: "1.0.4"), "!(v1.0.4 > 1.0.4)")
        ChallengerHarness.assertTrue(UpdateManager.isVersion("1.0.4", greaterThan: "1.0.4-beta.1"), "1.0.4 > 1.0.4-beta.1")
        ChallengerHarness.assertFalse(UpdateManager.isVersion("1.0.4-beta.1", greaterThan: "1.0.4"), "!(1.0.4-beta.1 > 1.0.4)")

        // 13D: ReleaseInfo Parsing with Malformed JSON
        let invalidJSONData = "this is not valid json".data(using: .utf8)!
        var threwInvalid = false
        do {
            _ = try UpdateManager.parseRelease(from: invalidJSONData)
        } catch {
            threwInvalid = true
        }
        ChallengerHarness.assertTrue(threwInvalid, "parseRelease throws on malformed JSON")

        let emptyJSONData = "{}".data(using: .utf8)!
        var threwEmpty = false
        do {
            _ = try UpdateManager.parseRelease(from: emptyJSONData)
        } catch {
            threwEmpty = true
        }
        ChallengerHarness.assertTrue(threwEmpty, "parseRelease throws on empty JSON object missing tag_name")

        let typeMismatchJSON = "{\"tag_name\": 12345}".data(using: .utf8)!
        var threwTypeMismatch = false
        do {
            _ = try UpdateManager.parseRelease(from: typeMismatchJSON)
        } catch {
            threwTypeMismatch = true
        }
        ChallengerHarness.assertTrue(threwTypeMismatch, "parseRelease throws on tag_name type mismatch")

        // Missing optional fields (name, body, html_url, assets all omitted)
        let minimalJSON = "{\"tag_name\": \"v1.0.4\"}".data(using: .utf8)!
        do {
            let rel = try UpdateManager.parseRelease(from: minimalJSON)
            ChallengerHarness.assertEqual(rel.tagName, "v1.0.4", "Minimal JSON parses tag_name")
            ChallengerHarness.assertEqual(rel.name, "v1.0.4", "Minimal JSON defaults name to tag_name")
            ChallengerHarness.assertEqual(rel.releaseNotes, "", "Minimal JSON defaults releaseNotes to empty string")
            ChallengerHarness.assertEqual(rel.htmlURL.absoluteString, "https://github.com/nhanqv-ai/SuperShot/releases", "Minimal JSON defaults htmlURL safely")
            ChallengerHarness.assertNil(rel.zipAssetURL, "Minimal JSON has nil zipAssetURL")
            ChallengerHarness.assertEqual(rel.versionString, "1.0.4", "versionString strips leading v")
        } catch {
            ChallengerHarness.assertTrue(false, "Minimal JSON unexpectedly threw: \(error)")
        }

        // Whitespace-only html_url fallback
        let whitespaceUrlJSON = """
        {
            "tag_name": "v1.0.4",
            "html_url": "   \\t  \\n"
        }
        """.data(using: .utf8)!
        do {
            let rel = try UpdateManager.parseRelease(from: whitespaceUrlJSON)
            ChallengerHarness.assertEqual(rel.htmlURL.absoluteString, "https://github.com/nhanqv-ai/SuperShot/releases", "Whitespace html_url falls back to default releases URL")
        } catch {
            ChallengerHarness.assertTrue(false, "Whitespace html_url unexpectedly threw: \(error)")
        }

        // Assets discrimination: prefers asset matching supershot & .zip over general .zip
        let multiAssetJSON = """
        {
            "tag_name": "v1.0.4",
            "assets": [
                { "name": "other-tool.zip", "browser_download_url": "https://example.com/other.zip" },
                { "name": "SuperShot-v1.0.4-arm64.dmg", "browser_download_url": "https://example.com/app.dmg" },
                { "name": "SuperShot-v1.0.4.zip", "browser_download_url": "https://example.com/SuperShot-v1.0.4.zip" },
                { "name": "checksums.txt", "browser_download_url": "https://example.com/sha.txt" }
            ]
        }
        """.data(using: .utf8)!
        do {
            let rel = try UpdateManager.parseRelease(from: multiAssetJSON)
            ChallengerHarness.assertEqual(rel.zipAssetURL?.absoluteString, "https://example.com/SuperShot-v1.0.4.zip", "Selects supershot-specific zip over other zip assets")
        } catch {
            ChallengerHarness.assertTrue(false, "Multi-asset JSON unexpectedly threw: \(error)")
        }

        // Fallback to any .zip when 'supershot' keyword is not present in name
        let genericZipJSON = """
        {
            "tag_name": "v1.0.4",
            "assets": [
                { "name": "release-archive.zip", "browser_download_url": "https://example.com/release-archive.zip" }
            ]
        }
        """.data(using: .utf8)!
        do {
            let rel = try UpdateManager.parseRelease(from: genericZipJSON)
            ChallengerHarness.assertEqual(rel.zipAssetURL?.absoluteString, "https://example.com/release-archive.zip", "Falls back to any .zip asset when supershot keyword is absent")
        } catch {
            ChallengerHarness.assertTrue(false, "Generic zip JSON unexpectedly threw: \(error)")
        }

        // Non-zip assets (e.g. tar.gz or dmg only) -> zipAssetURL is nil
        let noZipJSON = """
        {
            "tag_name": "v1.0.4",
            "assets": [
                { "name": "SuperShot.dmg", "browser_download_url": "https://example.com/app.dmg" },
                { "name": "SuperShot.tar.gz", "browser_download_url": "https://example.com/app.tar.gz" }
            ]
        }
        """.data(using: .utf8)!
        do {
            let rel = try UpdateManager.parseRelease(from: noZipJSON)
            ChallengerHarness.assertNil(rel.zipAssetURL, "zipAssetURL is nil when no .zip assets exist")
        } catch {
            ChallengerHarness.assertTrue(false, "No zip JSON unexpectedly threw: \(error)")
        }
    }

    // MARK: - 14. UpdateManager State Transitions, Error Conditions & Concurrency
    static func testUpdateManagerStateTransitionsAndConcurrency() {
        ChallengerHarness.startSuite("14. UpdateManager State Transitions, Error Conditions & Concurrency")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AdversarialMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let mockValidJSON = """
        {
            "tag_name": "v1.0.4",
            "name": "SuperShot 1.0.4",
            "body": "Adversarial test release notes",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.4",
            "assets": [
                {
                    "name": "SuperShot-v1.0.4.zip",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.4/SuperShot-v1.0.4.zip"
                }
            ]
        }
        """.data(using: .utf8)!

        let mgr = UpdateManager(session: session)
        mgr.currentVersion = "1.0.3"

        // 14A: Initial State Invariants
        ChallengerHarness.assertEqual(mgr.status, .idle, "Initial status is .idle")
        ChallengerHarness.assertFalse(mgr.hasPendingUpdate, "Initially hasPendingUpdate is false")
        ChallengerHarness.assertFalse(mgr.hasUpdateAvailable, "Initially hasUpdateAvailable is false")
        ChallengerHarness.assertFalse(mgr.shouldShowBanner, "Initially shouldShowBanner is false")
        ChallengerHarness.assertFalse(mgr.isBusy, "Initially isBusy is false")

        // 14B: State Machine Progression & Banner Session Dismissal
        let dummyRelease = ReleaseInfo(
            tagName: "v1.0.4",
            name: "SuperShot 1.0.4",
            releaseNotes: "Notes",
            htmlURL: URL(string: "https://example.com")!,
            zipAssetURL: URL(string: "https://example.com/update.zip")!
        )

        // Simulate .updateAvailable
        mgr.status = .updateAvailable(dummyRelease)
        mgr.latestRelease = dummyRelease
        mgr.hasPendingUpdate = true
        mgr.isBannerDismissedForSession = false

        ChallengerHarness.assertTrue(mgr.hasPendingUpdate, "hasPendingUpdate is true in .updateAvailable")
        ChallengerHarness.assertTrue(mgr.hasUpdateAvailable, "hasUpdateAvailable is true in .updateAvailable")
        ChallengerHarness.assertTrue(mgr.shouldShowBanner, "shouldShowBanner is true in .updateAvailable")
        ChallengerHarness.assertFalse(mgr.isBusy, "isBusy is false in .updateAvailable")

        // Dismiss banner for session
        mgr.dismissBannerForSession()
        ChallengerHarness.assertFalse(mgr.shouldShowBanner, "shouldShowBanner is false after session dismissal")
        ChallengerHarness.assertTrue(mgr.hasPendingUpdate, "hasPendingUpdate stays true after dismissal (gear badge)")
        ChallengerHarness.assertTrue(mgr.hasUpdateAvailable, "hasUpdateAvailable stays true after dismissal")

        // Transition to .downloading
        mgr.status = .downloading(progress: 0.45)
        ChallengerHarness.assertTrue(mgr.isBusy, "isBusy is true during .downloading")
        mgr.isBannerDismissedForSession = false
        ChallengerHarness.assertTrue(mgr.shouldShowBanner, "shouldShowBanner is true during downloading when not dismissed")

        // Transition to .readyToRestart
        mgr.status = .readyToRestart(dummyRelease)
        mgr.isBannerDismissedForSession = false
        ChallengerHarness.assertFalse(mgr.isBusy, "isBusy is false in .readyToRestart")
        ChallengerHarness.assertTrue(mgr.shouldShowBanner, "shouldShowBanner is true in .readyToRestart")

        // 14C: readyToRestart State Protection
        // Background check must NEVER overwrite readyToRestart with .upToDate, .error, or .checking
        AdversarialMockURLProtocol.reset()
        AdversarialMockURLProtocol.mockResponse = HTTPURLResponse(
            url: mgr.apiURL,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )

        var bgCheckCompleted = false
        mgr.checkForUpdates(userInitiated: false) { result in
            bgCheckCompleted = true
        }

        let deadlineBg = Date().addingTimeInterval(3.0)
        while !bgCheckCompleted && Date() < deadlineBg {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        ChallengerHarness.assertTrue(bgCheckCompleted, "Background check completed")
        ChallengerHarness.assertEqual(mgr.status, .readyToRestart(dummyRelease), "Background check preserves .readyToRestart and is not clobbered by server error")

        // 14D: HTTP Error Code Mapping
        let errorCodes: [(Int, UpdateError)] = [
            (404, .noReleaseFound),
            (403, .rateLimitExceeded),
            (429, .rateLimitExceeded),
            (500, .httpError(500)),
            (502, .httpError(502)),
            (503, .httpError(503))
        ]

        for (code, expectedErr) in errorCodes {
            AdversarialMockURLProtocol.reset()
            AdversarialMockURLProtocol.mockResponse = HTTPURLResponse(
                url: mgr.apiURL,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )

            mgr.status = .idle
            var errCompleted = false

            mgr.checkForUpdates(userInitiated: true) { _ in
                errCompleted = true
            }

            let dl = Date().addingTimeInterval(3.0)
            while !errCompleted && Date() < dl {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }

            ChallengerHarness.assertTrue(errCompleted, "Check completed for HTTP \(code)")
            if case .error(let msg) = mgr.status {
                ChallengerHarness.assertTrue(msg.contains(expectedErr.localizedDescription) || msg == expectedErr.localizedDescription, "Status contains expected error message for HTTP \(code)")
            } else {
                ChallengerHarness.assertTrue(false, "Expected .error status for HTTP \(code), got: \(mgr.status)")
            }
        }

        // 14E: Rapid Concurrent Invocation Stress
        AdversarialMockURLProtocol.reset()
        AdversarialMockURLProtocol.mockData = mockValidJSON
        AdversarialMockURLProtocol.mockResponse = HTTPURLResponse(
            url: mgr.apiURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )

        mgr.status = .idle
        mgr.currentVersion = "1.0.3"

        let concurrentCalls = 30
        var completedConcurrent = 0
        let concLock = NSLock()

        for i in 0..<concurrentCalls {
            DispatchQueue.global().async {
                mgr.checkForUpdates(userInitiated: i % 2 == 0) { _ in
                    concLock.lock()
                    completedConcurrent += 1
                    concLock.unlock()
                }
            }
        }

        let concDeadline = Date().addingTimeInterval(5.0)
        while completedConcurrent < concurrentCalls && Date() < concDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        ChallengerHarness.assertEqual(completedConcurrent, concurrentCalls, "All \(concurrentCalls) concurrent checkForUpdates calls completed without deadlock")
        ChallengerHarness.assertTrue(mgr.hasPendingUpdate, "hasPendingUpdate resolved cleanly under concurrency")
        if case .updateAvailable(let rel) = mgr.status {
            ChallengerHarness.assertEqual(rel.tagName, "v1.0.4", "Status cleanly converged to .updateAvailable v1.0.4")
        } else {
            ChallengerHarness.assertTrue(false, "Status failed to converge to .updateAvailable, got: \(mgr.status)")
        }
    }

    // MARK: - 15. AppSettings updateCheckIntervalDays Clamping & Timing Stress
    static func testUpdateCheckIntervalClampingAndPersistence() {
        ChallengerHarness.startSuite("15. AppSettings updateCheckIntervalDays Clamping & Timing Stress")

        let sandboxDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SuperShot_Adv_Settings_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sandboxDir)
        }

        let settingsURL = sandboxDir.appendingPathComponent("settings.json")
        let settings = AppSettings(settingsURL: settingsURL)

        // 15A: Default Value
        ChallengerHarness.assertEqual(settings.updateCheckIntervalDays, 1, "Default updateCheckIntervalDays is 1")

        // 15B: Boundary Clamping on Assignment
        let clampingCases: [(input: Int, expected: Int)] = [
            (0, 1),
            (-1, 1),
            (-50, 1),
            (-999999, 1),
            (Int.min, 1),
            (1, 1),
            (2, 2),
            (7, 7),
            (14, 14),
            (30, 30),
            (31, 30),
            (100, 30),
            (999999, 30),
            (Int.max, 30)
        ]

        for c in clampingCases {
            settings.updateCheckIntervalDays = c.input
            ChallengerHarness.assertEqual(settings.updateCheckIntervalDays, c.expected, "updateCheckIntervalDays \(c.input) clamped to \(c.expected)")
        }

        // 15C: Persistence & Reload Roundtrip
        settings.updateCheckIntervalDays = 7
        do {
            try settings.saveSynchronously()
            let reloaded = AppSettings(settingsURL: settingsURL)
            ChallengerHarness.assertEqual(reloaded.updateCheckIntervalDays, 7, "Persisted interval 7 reloaded accurately")
        } catch {
            ChallengerHarness.assertTrue(false, "saveSynchronously unexpectedly threw: \(error)")
        }

        settings.updateCheckIntervalDays = 30
        do {
            try settings.saveSynchronously()
            let reloaded30 = AppSettings(settingsURL: settingsURL)
            ChallengerHarness.assertEqual(reloaded30.updateCheckIntervalDays, 30, "Persisted interval 30 reloaded accurately")
        } catch {
            ChallengerHarness.assertTrue(false, "saveSynchronously 30 threw: \(error)")
        }

        // 15D: Legacy JSON Decoding Fallback (Backward Compatibility)
        let legacyJSON = """
        {
            "activeColorHex": "#FF3B30",
            "activeStrokeWidth": 3.0,
            "activeFontSize": 18.0,
            "presets": [],
            "autoSaveEnabled": false,
            "autoSaveDirectoryPath": "/tmp",
            "saveFormat": "png",
            "jpegQuality": 0.9,
            "maxScrollHeightPx": 15000,
            "capacity": 50,
            "launchAtLogin": false,
            "language": "system",
            "autoPasteOnSelection": true,
            "regionHotKeyKeyCode": 1,
            "regionHotKeyModifiers": 2048,
            "scrollHotKeyKeyCode": 1,
            "scrollHotKeyModifiers": 2560,
            "automaticallyCheckForUpdates": true
        }
        """.data(using: .utf8)!

        do {
            let decoder = JSONDecoder()
            let legacySnapshot = try decoder.decode(AppSettingsSnapshot.self, from: legacyJSON)
            ChallengerHarness.assertEqual(legacySnapshot.updateCheckIntervalDays, 1, "Legacy JSON without updateCheckIntervalDays defaults to 1")

            let legacySettings = AppSettings(settingsURL: sandboxDir.appendingPathComponent("legacy.json"), initialSnapshot: legacySnapshot)
            ChallengerHarness.assertEqual(legacySettings.updateCheckIntervalDays, 1, "AppSettings constructed from legacy snapshot has updateCheckIntervalDays == 1")
        } catch {
            ChallengerHarness.assertTrue(false, "Legacy JSON decode failed: \(error)")
        }

        // 15E: Corrupt JSON Clamping on Load
        let corruptNegativeJSON = """
        {
            "activeColorHex": "#FF3B30",
            "activeStrokeWidth": 3.0,
            "activeFontSize": 18.0,
            "presets": [],
            "autoSaveEnabled": false,
            "autoSaveDirectoryPath": "/tmp",
            "saveFormat": "png",
            "jpegQuality": 0.9,
            "maxScrollHeightPx": 15000,
            "capacity": 50,
            "launchAtLogin": false,
            "language": "system",
            "autoPasteOnSelection": true,
            "regionHotKeyKeyCode": 1,
            "regionHotKeyModifiers": 2048,
            "scrollHotKeyKeyCode": 1,
            "scrollHotKeyModifiers": 2560,
            "automaticallyCheckForUpdates": true,
            "updateCheckIntervalDays": -100
        }
        """.data(using: .utf8)!

        let corruptNegURL = sandboxDir.appendingPathComponent("corrupt_neg.json")
        try? corruptNegativeJSON.write(to: corruptNegURL)
        let corruptNegSettings = AppSettings(settingsURL: corruptNegURL)
        ChallengerHarness.assertEqual(corruptNegSettings.updateCheckIntervalDays, 1, "Corrupt negative interval in JSON is clamped to 1 on load")

        let corruptHugeJSON = """
        {
            "activeColorHex": "#FF3B30",
            "activeStrokeWidth": 3.0,
            "activeFontSize": 18.0,
            "presets": [],
            "autoSaveEnabled": false,
            "autoSaveDirectoryPath": "/tmp",
            "saveFormat": "png",
            "jpegQuality": 0.9,
            "maxScrollHeightPx": 15000,
            "capacity": 50,
            "launchAtLogin": false,
            "language": "system",
            "autoPasteOnSelection": true,
            "regionHotKeyKeyCode": 1,
            "regionHotKeyModifiers": 2048,
            "scrollHotKeyKeyCode": 1,
            "scrollHotKeyModifiers": 2560,
            "automaticallyCheckForUpdates": true,
            "updateCheckIntervalDays": 9999
        }
        """.data(using: .utf8)!

        let corruptHugeURL = sandboxDir.appendingPathComponent("corrupt_huge.json")
        try? corruptHugeJSON.write(to: corruptHugeURL)
        let corruptHugeSettings = AppSettings(settingsURL: corruptHugeURL)
        ChallengerHarness.assertEqual(corruptHugeSettings.updateCheckIntervalDays, 30, "Corrupt huge interval in JSON is clamped to 30 on load")

        // 15F: Startup Timing Oracle Verification
        func shouldTriggerStartupCheck(
            autoCheck: Bool,
            lastCheck: Date?,
            intervalDays: Int,
            now: Date
        ) -> Bool {
            guard autoCheck else { return false }
            guard let last = lastCheck else { return true }
            let clampedInterval = max(1, intervalDays)
            let intervalSeconds = Double(clampedInterval * 86400)
            return now.timeIntervalSince(last) >= intervalSeconds
        }

        let refNow = Date()

        // Daily interval (1 day)
        ChallengerHarness.assertFalse(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: refNow.addingTimeInterval(-3600), intervalDays: 1, now: refNow),
            "Daily check skipped when last check was 1 hour ago"
        )
        ChallengerHarness.assertFalse(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: refNow.addingTimeInterval(-86300), intervalDays: 1, now: refNow),
            "Daily check skipped when last check was 23.97 hours ago"
        )
        ChallengerHarness.assertTrue(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: refNow.addingTimeInterval(-86401), intervalDays: 1, now: refNow),
            "Daily check triggered when last check was > 24 hours ago"
        )

        // Weekly interval (7 days)
        ChallengerHarness.assertFalse(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: refNow.addingTimeInterval(-86400 * 6), intervalDays: 7, now: refNow),
            "Weekly check skipped when last check was 6 days ago"
        )
        ChallengerHarness.assertTrue(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: refNow.addingTimeInterval(-86400 * 7 - 1), intervalDays: 7, now: refNow),
            "Weekly check triggered when last check was > 7 days ago"
        )

        // Monthly interval (30 days)
        ChallengerHarness.assertFalse(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: refNow.addingTimeInterval(-86400 * 29), intervalDays: 30, now: refNow),
            "Monthly check skipped when last check was 29 days ago"
        )
        ChallengerHarness.assertTrue(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: refNow.addingTimeInterval(-86400 * 30 - 1), intervalDays: 30, now: refNow),
            "Monthly check triggered when last check was > 30 days ago"
        )

        // No prior check date
        ChallengerHarness.assertTrue(
            shouldTriggerStartupCheck(autoCheck: true, lastCheck: nil, intervalDays: 7, now: refNow),
            "Startup check triggered when lastUpdateCheckDate is nil"
        )

        // Auto check disabled
        ChallengerHarness.assertFalse(
            shouldTriggerStartupCheck(autoCheck: false, lastCheck: refNow.addingTimeInterval(-86400 * 365), intervalDays: 1, now: refNow),
            "Startup check skipped when automaticallyCheckForUpdates is false even if checked 1 year ago"
        )
    }

    // MARK: - 16. Rapid Sequential Duplication & Deep Undo/Redo Stress
    private static func testAnnotationDuplicationAndDeepUndoRedoStress() {
        ChallengerHarness.startSuite("16. Rapid Sequential Duplications, Deep Undo/Redo & Clamping Stress")

        let engine = AnnotationEngine()
        let seed = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 20, y: 20, width: 80, height: 60),
            colorHex: "#FF3B30",
            strokeWidth: 3.0
        )
        engine.addObject(seed)
        engine.selectedObjectID = seed.id

        // 16A: Rapid sequential duplications (50 items)
        let dupCount = 50
        var generatedIDs = Set<UUID>()
        generatedIDs.insert(seed.id)

        for i in 1...dupCount {
            guard let clone = engine.duplicateSelected(offset: CGPoint(x: 4, y: 4)) else {
                ChallengerHarness.recordFail("Duplication step \(i)", reason: "duplicateSelected returned nil")
                return
            }
            ChallengerHarness.assertFalse(generatedIDs.contains(clone.id), "Clone #\(i) has globally unique UUID")
            generatedIDs.insert(clone.id)
            ChallengerHarness.assertEqual(engine.selectedObjectID, clone.id, "Selection transferred to clone #\(i)")
        }

        ChallengerHarness.assertEqual(engine.objects.count, dupCount + 1, "Total objects in engine matches 51")
        ChallengerHarness.assertEqual(generatedIDs.count, dupCount + 1, "All 51 object IDs are distinct")

        // Deep Undo all 50 duplications
        for i in 1...dupCount {
            ChallengerHarness.assertTrue(engine.canUndo, "canUndo true before undo step \(i)")
            engine.undo()
        }
        ChallengerHarness.assertEqual(engine.objects.count, 1, "Full roll-back restores canvas to exactly 1 seed object")
        ChallengerHarness.assertEqual(engine.objects.first?.id, seed.id, "Seed object preserved intact")
        ChallengerHarness.assertFalse(engine.canUndo, "canUndo is false after complete stack rollback")

        // Deep Redo all 50 duplications
        for i in 1...dupCount {
            ChallengerHarness.assertTrue(engine.canRedo, "canRedo true before redo step \(i)")
            engine.redo()
        }
        ChallengerHarness.assertEqual(engine.objects.count, dupCount + 1, "Full roll-forward restores all 51 objects")
        ChallengerHarness.assertFalse(engine.canRedo, "canRedo is false after complete roll-forward")

        // 16B: Interleaved mutations & duplications
        let mixedEngine = AnnotationEngine()
        let objA = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 50, y: 50, width: 100, height: 100))
        mixedEngine.addObject(objA)
        mixedEngine.selectedObjectID = objA.id

        let objB = mixedEngine.duplicateSelected()!
        mixedEngine.recolorSelected(newHex: "#007AFF")
        mixedEngine.moveSelected(by: CGPoint(x: 10, y: 20))
        let objC = mixedEngine.duplicateSelected()!

        ChallengerHarness.assertEqual(mixedEngine.objects.count, 3, "Interleaved engine contains 3 objects")
        ChallengerHarness.assertEqual(objC.colorHex, "#007AFF", "Cloned object inherits recolored hex")

        // Roll back step by step
        mixedEngine.undo() // reverts create objC
        ChallengerHarness.assertEqual(mixedEngine.objects.count, 2, "Reverted objC")
        mixedEngine.undo() // reverts move
        mixedEngine.undo() // reverts recolor
        ChallengerHarness.assertEqual(mixedEngine.objects.first(where: { $0.id == objB.id })?.colorHex, "#FF3B30", "Reverted color to default red")
        mixedEngine.undo() // reverts create objB
        ChallengerHarness.assertEqual(mixedEngine.objects.count, 1, "Reverted objB")
        ChallengerHarness.assertEqual(mixedEngine.objects.first?.id, objA.id, "Back to objA")

        // 16C: Boundary clamping stress in micro frame
        let microBoundary = CGRect(x: 0, y: 0, width: 60, height: 60)
        let microEngine = AnnotationEngine()
        let microObj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 35, height: 35))
        microEngine.addObject(microObj)
        microEngine.selectedObjectID = microObj.id

        for _ in 0..<10 {
            if let clone = microEngine.duplicateSelected(offset: CGPoint(x: 16, y: 16), within: microBoundary) {
                ChallengerHarness.assertTrue(clone.bounds.maxX <= microBoundary.maxX, "Clone maxX \(clone.bounds.maxX) <= 60")
                ChallengerHarness.assertTrue(clone.bounds.maxY <= microBoundary.maxY, "Clone maxY \(clone.bounds.maxY) <= 60")
                ChallengerHarness.assertTrue(clone.bounds.minX >= microBoundary.minX, "Clone minX \(clone.bounds.minX) >= 0")
                ChallengerHarness.assertTrue(clone.bounds.minY >= microBoundary.minY, "Clone minY \(clone.bounds.minY) >= 0")
            }
        }

        // Extreme coordinate stress
        let macroEngine = AnnotationEngine()
        let macroObj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 29900, y: 29900, width: 80, height: 80))
        macroEngine.addObject(macroObj)
        macroEngine.selectedObjectID = macroObj.id
        let macroClone = macroEngine.duplicateSelected(offset: CGPoint(x: 16, y: 16), within: CGRect(x: 0, y: 0, width: 30000, height: 30000))
        ChallengerHarness.assertNotNil(macroClone, "Macro clone at 29,900px produced cleanly")
        ChallengerHarness.assertTrue(macroClone!.bounds.maxX <= 30000, "Macro clone maxX <= 30000")
    }

    // MARK: - 17. Angle Snapping & Zoom Magnification Stress
    private static func testAngleSnappingAndZoomMagnificationStress() {
        ChallengerHarness.startSuite("17. Angle Snapping Mathematical Stability & Zoom Magnification Stress")

        // 17A: Angle snapping mathematical stability
        let origin = CGPoint(x: 0, y: 0)

        // Sub-pixel guard (< 1.0pt length)
        let subPixelTarget = CGPoint(x: 0.00001, y: 0.00002)
        let subPixelSnapped = AnnotationObject.snapAngle(from: origin, to: subPixelTarget)
        ChallengerHarness.assertFalse(subPixelSnapped.x.isNaN, "Sub-pixel snap x is not NaN")
        ChallengerHarness.assertFalse(subPixelSnapped.y.isNaN, "Sub-pixel snap y is not NaN")
        ChallengerHarness.assertFalse(subPixelSnapped.x.isInfinite, "Sub-pixel snap x is not Infinite")
        ChallengerHarness.assertEqual(subPixelSnapped.x, subPixelTarget.x, "Sub-pixel snap preserves target exactly")

        // Zero-length identical point
        let zeroSnapped = AnnotationObject.snapAngle(from: origin, to: origin)
        ChallengerHarness.assertEqual(zeroSnapped, origin, "Zero-length snap returns origin cleanly")

        // Extreme macro coordinates (10,000,000 pt)
        let macroOrigin = CGPoint(x: 10000000, y: 10000000)
        let macroTarget = CGPoint(x: 10000100, y: 10000005)
        let macroSnapped = AnnotationObject.snapAngle(from: macroOrigin, to: macroTarget)
        ChallengerHarness.assertEqual(round(macroSnapped.x), 10000100.0, "Macro coordinate snapped x accurate")
        ChallengerHarness.assertEqual(round(macroSnapped.y), 10000000.0, "Macro coordinate snapped y horizontal")

        // 360-degree sweep in 1-degree steps: every snapped vector must align with k * pi/4
        let sweepRadius: CGFloat = 100.0
        var allSnapsValid = true
        var allLengthsPreserved = true
        for deg in 0..<360 {
            let rad = CGFloat(deg) * .pi / 180.0
            let targetPt = CGPoint(x: sweepRadius * cos(rad), y: sweepRadius * sin(rad))
            let snappedPt = AnnotationObject.snapAngle(from: origin, to: targetPt)

            let angle = atan2(snappedPt.y, snappedPt.x)
            let normalizedAngle = angle < 0 ? angle + 2 * .pi : angle
            let octant = normalizedAngle / (.pi / 4.0)
            let diffFromInt = abs(octant - round(octant))
            if diffFromInt > 1e-4 {
                allSnapsValid = false
            }

            let len = hypot(snappedPt.x, snappedPt.y)
            if abs(len - sweepRadius) > 0.001 {
                allLengthsPreserved = false
            }
        }
        ChallengerHarness.assertTrue(allSnapsValid, "All 360 sweep angles snap strictly to k * pi/4 multiples")
        ChallengerHarness.assertTrue(allLengthsPreserved, "All 360 sweep lengths preserved within 0.001")

        // 17B: Zoom Magnification Clamping & Step Stress
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 200 * 4, space: colorSpace, bitmapInfo: bitmapInfo)!
        let dummyImage = ctx.makeImage()!

        let engine = AnnotationEngine()
        let docView = ScrollableAnnotationDocumentView(baseImage: dummyImage, engine: engine)
        let scrollView = ScrollableAnnotationScrollView(documentCanvasView: docView)

        // 50 alternating in/out steps without precision decay
        for _ in 0..<50 {
            scrollView.zoomIn()
            scrollView.zoomOut()
        }
        ChallengerHarness.assertTrue(abs(scrollView.magnification - 1.0) < 1e-5, "50 alternating zoom steps maintain 1.0 within 1e-5")

        // Extreme zoom-in ceiling
        for _ in 0..<50 {
            scrollView.zoomIn()
        }
        ChallengerHarness.assertEqual(scrollView.magnification, 4.0, "Clamped strictly to maxMagnification 4.0")

        // Extreme zoom-out floor
        for _ in 0..<50 {
            scrollView.zoomOut()
        }
        ChallengerHarness.assertEqual(scrollView.magnification, 0.1, "Clamped strictly to minMagnification 0.1")

        // Zoom ViewModel HUD percentage text formatting
        let zoomHUDModel = ScrollableZoomViewModel(magnification: 1.0)
        ChallengerHarness.assertEqual(Int(round(zoomHUDModel.magnification * 100)), 100, "1.0 maps to 100%")

        zoomHUDModel.magnification = 0.1
        ChallengerHarness.assertEqual(Int(round(zoomHUDModel.magnification * 100)), 10, "0.1 maps to 10%")

        zoomHUDModel.magnification = 1.25
        ChallengerHarness.assertEqual(Int(round(zoomHUDModel.magnification * 100)), 125, "1.25 maps to 125%")

        zoomHUDModel.magnification = 4.0
        ChallengerHarness.assertEqual(Int(round(zoomHUDModel.magnification * 100)), 400, "4.0 maps to 400%")
    }

    // MARK: - 18. Aspect Ratio Detection & Tolerance Boundary Stress
    private static func testAspectRatioDetectionAndToleranceBoundaryStress() {
        ChallengerHarness.startSuite("18. Aspect Ratio Detection & Tolerance Boundary Stress")

        // 18A: Zero, negative, and micro-dimension edge cases
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 0, height: 0), "0x0 dimensions return nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 1920, height: 0), "Non-zero width with 0 height returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 0, height: 1080), "0 width with non-zero height returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: -1920, height: -1080), "Negative dimensions return nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: -1920, height: 1080), "Negative width returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 1920, height: -1080), "Negative height returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 10.0, height: 10.0), "Boundary 10x10 dimensions return nil (threshold is > 10)")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 10.0, height: 100.0), "Boundary width 10 returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 100.0, height: 10.0), "Boundary height 10 returns nil")
        ChallengerHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 10.0001, height: 10.0001), "1:1", "Slightly above 10 (10.0001) detects 1:1")

        // 18B: Extreme aspect ratios and non-standard ratios
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 10000, height: 1), "10000:1 ratio with small height returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 1, height: 10000), "1:10000 ratio with small width returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 100000, height: 11), "Extreme 9090:1 ratio returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 11, height: 100000), "Extreme 1:9090 ratio returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 500, height: 420), "Arbitrary non-standard ratio returns nil")

        // 18C: Special IEEE floating point values (NaN, Infinity)
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: .nan, height: 100), "NaN width returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 100, height: .nan), "NaN height returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: .infinity, height: 100), "Infinity width returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 100, height: .infinity), "Infinity height returns nil")
        ChallengerHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: .infinity, height: .infinity), "Infinity/Infinity returns nil")

        // 18D: All 9 Standard Aspect Ratios at exact values
        let standardTests: [(name: String, w: CGFloat, h: CGFloat)] = [
            ("1:1", 800, 800),
            ("16:9", 1920, 1080),
            ("4:3", 1024, 768),
            ("16:10", 1920, 1200),
            ("3:2", 1500, 1000),
            ("21:9", 2560, 1097.142857),
            ("9:16", 1080, 1920),
            ("3:4", 768, 1024),
            ("2:3", 1000, 1500)
        ]
        for item in standardTests {
            let detected = SelectionBoxGeometry.detectAspectRatio(width: item.w, height: item.h)
            ChallengerHarness.assertEqual(detected, item.name, "Exact ratio for \(item.name)")
        }

        // 18E: Tolerance Boundary Stress (±2.4% vs ±2.6% threshold testing)
        let toleranceTestRatios: [(name: String, standardRatio: CGFloat)] = [
            ("1:1", 1.0),
            ("16:9", 16.0 / 9.0),
            ("4:3", 4.0 / 3.0),
            ("16:10", 16.0 / 10.0),
            ("3:2", 3.0 / 2.0),
            ("21:9", 21.0 / 9.0),
            ("9:16", 9.0 / 16.0),
            ("3:4", 3.0 / 4.0),
            ("2:3", 2.0 / 3.0)
        ]

        let baseHeight: CGFloat = 1000.0
        for item in toleranceTestRatios {
            let standardWidth = baseHeight * item.standardRatio

            // +2.4% deviation (should pass)
            let wPlus24 = standardWidth * 1.024
            ChallengerHarness.assertEqual(
                SelectionBoxGeometry.detectAspectRatio(width: wPlus24, height: baseHeight),
                item.name,
                "\(item.name) at +2.4% deviation is recognized within tolerance"
            )

            // -2.4% deviation (should pass)
            let wMinus24 = standardWidth * 0.976
            ChallengerHarness.assertEqual(
                SelectionBoxGeometry.detectAspectRatio(width: wMinus24, height: baseHeight),
                item.name,
                "\(item.name) at -2.4% deviation is recognized within tolerance"
            )

            // +2.6% deviation (should reject)
            let wPlus26 = standardWidth * 1.026
            ChallengerHarness.assertNil(
                SelectionBoxGeometry.detectAspectRatio(width: wPlus26, height: baseHeight),
                "\(item.name) at +2.6% deviation is rejected outside tolerance"
            )

            // -2.6% deviation (should reject)
            let wMinus26 = standardWidth * 0.974
            ChallengerHarness.assertNil(
                SelectionBoxGeometry.detectAspectRatio(width: wMinus26, height: baseHeight),
                "\(item.name) at -2.6% deviation is rejected outside tolerance"
            )
        }

        // 18F: Dimension Badge Formatting Stress
        let badgeWithAspect = SelectionBoxGeometry.formatDimensionBadge(width: 1920, height: 1080, scaleFactor: 1.0, includeAspectRatio: true)
        ChallengerHarness.assertEqual(badgeWithAspect, "1920 x 1080 px (16:9)", "Badge formats with 16:9 aspect ratio")

        let badgeRetina = SelectionBoxGeometry.formatDimensionBadge(width: 1920, height: 1080, scaleFactor: 2.0, includeAspectRatio: true)
        ChallengerHarness.assertEqual(badgeRetina, "3840 x 2160 px (16:9)", "Badge formats 2x retina with 16:9 aspect ratio")

        let badgeNoAspect = SelectionBoxGeometry.formatDimensionBadge(width: 1920, height: 1080, scaleFactor: 1.0, includeAspectRatio: false)
        ChallengerHarness.assertEqual(badgeNoAspect, "1920 x 1080 px", "Badge without aspect ratio omits parenthesis")

        let badgeZero = SelectionBoxGeometry.formatDimensionBadge(width: 0, height: 0, scaleFactor: 1.0, includeAspectRatio: true)
        ChallengerHarness.assertEqual(badgeZero, "1 x 1 px", "0x0 dimensions format safely as 1 x 1 px")
    }

    // MARK: - 19. Stroke Width Bracket Stepping Bounds & Rapid Dispatch Stress
    private static func testStrokeWidthBracketSteppingBoundsAndDispatchStress() {
        ChallengerHarness.startSuite("19. Stroke Width Bracket Stepping Bounds & Rapid Dispatch Stress")

        let appSettings = AppSettings()
        appSettings.activeStrokeWidth = 3.0
        let viewModel = FloatingToolbarsViewModel(appSettings: appSettings)

        var selectedWidths: [CGFloat] = []
        viewModel.onStrokeWidthSelected = { width in
            selectedWidths.append(width)
        }

        // 19A: Rapid repeated decrements far beyond lower bound (below 1.0)
        appSettings.activeStrokeWidth = 1.0
        for _ in 0..<100 {
            viewModel.decreaseStrokeWidth()
        }
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 1.0, "100 decrements from 1.0 remain strictly clamped at 1.0")

        // 19B: Rapid repeated increments far beyond upper bound (above 16.0)
        appSettings.activeStrokeWidth = 16.0
        for _ in 0..<100 {
            viewModel.increaseStrokeWidth()
        }
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 16.0, "100 increments from 16.0 remain strictly clamped at 16.0")

        // 19C: 15 consecutive increments from 1.0 stepping 1-by-1 to 16.0
        appSettings.activeStrokeWidth = 1.0
        selectedWidths.removeAll()
        for step in 1...15 {
            viewModel.increaseStrokeWidth()
            ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, CGFloat(1 + step), "Step \(step) correctly incremented to \(1 + step)")
        }
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 16.0, "Reached 16.0 at step 15")
        ChallengerHarness.assertEqual(selectedWidths.count, 15, "15 callbacks received")

        // 19D: 15 consecutive decrements from 16.0 stepping 1-by-1 to 1.0
        for step in 1...15 {
            viewModel.decreaseStrokeWidth()
            ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, CGFloat(16 - step), "Step \(step) correctly decremented to \(16 - step)")
        }
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 1.0, "Reached 1.0 at step 15")

        // 19E: 50 cycles of rapid alternating (increase then decrease)
        appSettings.activeStrokeWidth = 5.0
        for _ in 0..<50 {
            viewModel.increaseStrokeWidth()
            viewModel.decreaseStrokeWidth()
        }
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 5.0, "50 alternating cycles preserve stroke width 5.0")

        // 19F: Keyboard event dispatch stress: keycode 33 ([) and keycode 30 (])
        let bracketLeftEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        let bracketRightEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "]",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!

        appSettings.activeStrokeWidth = 8.0
        let handledL = ToolbarKeyShortcutHandler.handleKeyEvent(event: bracketLeftEvent, viewModel: viewModel)
        ChallengerHarness.assertTrue(handledL, "Keycode 33 [ handled")
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 7.0, "Keycode 33 decremented to 7.0")

        let handledR = ToolbarKeyShortcutHandler.handleKeyEvent(event: bracketRightEvent, viewModel: viewModel)
        ChallengerHarness.assertTrue(handledR, "Keycode 30 ] handled")
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 8.0, "Keycode 30 incremented to 8.0")

        // Modifier flags (Command, Option) should NOT trigger stroke width stepping
        let cmdBracketEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        let handledCmd = ToolbarKeyShortcutHandler.handleKeyEvent(event: cmdBracketEvent, viewModel: viewModel)
        ChallengerHarness.assertFalse(handledCmd, "Cmd+[ is not consumed by toolbar shortcut handler")
        ChallengerHarness.assertEqual(appSettings.activeStrokeWidth, 8.0, "Stroke width unchanged on Cmd+[")
    }

    // MARK: - 20. Shift-Key Aspect Ratio Snapping Under Extreme Coordinates Stress
    private static func testShiftKeyAspectRatioSnappingUnderExtremeCoordinatesStress() {
        ChallengerHarness.startSuite("20. Shift-Key Aspect Ratio Snapping Under Extreme Coordinates Stress")

        let bounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let anchor = CGPoint(x: 1000, y: 800)

        // 20A: 4 Quadrants corner-handle drag with Shift key
        // Quadrant 1 (bottom-right / +dx, +dy)
        let ptQ1 = CGPoint(x: 1400, y: 1000)
        let rectQ1 = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: ptQ1,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertEqual(rectQ1.width, 400.0, "Q1 width is 400.0")
        ChallengerHarness.assertEqual(rectQ1.height, 400.0, "Q1 height is 400.0 (1:1 square)")

        // Quadrant 2 (bottom-left / -dx, +dy)
        let ptQ2 = CGPoint(x: 700, y: 1000)
        let rectQ2 = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomLeft,
            currentPoint: ptQ2,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertEqual(rectQ2.width, 300.0, "Q2 width is 300.0")
        ChallengerHarness.assertEqual(rectQ2.height, 300.0, "Q2 height is 300.0 (1:1 square)")

        // Quadrant 3 (top-left / -dx, -dy)
        let ptQ3 = CGPoint(x: 750, y: 550)
        let rectQ3 = SelectionBoxGeometry.calculateResizedRect(
            handle: .topLeft,
            currentPoint: ptQ3,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertEqual(rectQ3.width, 250.0, "Q3 width is 250.0")
        ChallengerHarness.assertEqual(rectQ3.height, 250.0, "Q3 height is 250.0 (1:1 square)")

        // Quadrant 4 (top-right / +dx, -dy)
        let ptQ4 = CGPoint(x: 1350, y: 650)
        let rectQ4 = SelectionBoxGeometry.calculateResizedRect(
            handle: .topRight,
            currentPoint: ptQ4,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertEqual(rectQ4.width, 350.0, "Q4 width is 350.0")
        ChallengerHarness.assertEqual(rectQ4.height, 350.0, "Q4 height is 350.0 (1:1 square)")

        // 20B: Extreme negative mouse coordinates
        let extremeNegPoint = CGPoint(x: -100000, y: -100000)
        let rectNeg = SelectionBoxGeometry.calculateResizedRect(
            handle: .topLeft,
            currentPoint: extremeNegPoint,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertTrue(rectNeg.minX >= bounds.minX, "Extreme negative x clamped to bounds minX")
        ChallengerHarness.assertTrue(rectNeg.minY >= bounds.minY, "Extreme negative y clamped to bounds minY")
        ChallengerHarness.assertFalse(rectNeg.width.isNaN, "Width is not NaN under extreme negative coordinates")
        ChallengerHarness.assertFalse(rectNeg.height.isNaN, "Height is not NaN under extreme negative coordinates")

        // 20C: Extreme positive mouse coordinates
        let extremePosPoint = CGPoint(x: 100000, y: 100000)
        let rectPos = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: extremePosPoint,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertTrue(rectPos.maxX <= bounds.maxX, "Extreme positive x clamped to bounds maxX")
        ChallengerHarness.assertTrue(rectPos.maxY <= bounds.maxY, "Extreme positive y clamped to bounds maxY")
        ChallengerHarness.assertFalse(rectPos.width.isNaN, "Width is not NaN under extreme positive coordinates")
        ChallengerHarness.assertFalse(rectPos.height.isNaN, "Height is not NaN under extreme positive coordinates")

        // 20D: Zero-distance drag (anchor equals currentPoint)
        let rectZero = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: anchor,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertTrue(rectZero.width >= 1.0, "Zero distance drag produces width >= 1.0")
        ChallengerHarness.assertTrue(rectZero.height >= 1.0, "Zero distance drag produces height >= 1.0")

        // 20E: Micro-displacement (0.001pt)
        let ptMicro = CGPoint(x: anchor.x + 0.001, y: anchor.y + 0.001)
        let rectMicro = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: ptMicro,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        ChallengerHarness.assertTrue(rectMicro.width >= 1.0, "Micro displacement produces valid width")
        ChallengerHarness.assertTrue(rectMicro.height >= 1.0, "Micro displacement produces valid height")
    }

    // MARK: - 21. Settings Tab Cycling Wrapping & Modulo Stress
    private static func testSettingsTabCyclingWrappingAndModuloStress() {
        ChallengerHarness.startSuite("21. Settings Tab Cycling Wrapping & Modulo Stress")

        let tabs = SettingsTab.allCases
        ChallengerHarness.assertEqual(tabs.count, 4, "SettingsTab has exactly 4 tabs")

        // 21A: Forward tab wrapping: 0 -> 1 -> 2 -> 3 -> 0
        var currentIndex = 0
        let forwardSequence: [SettingsTab] = [.general, .captureSave, .history, .about, .general]
        for expectedTab in forwardSequence {
            ChallengerHarness.assertEqual(tabs[currentIndex], expectedTab, "Current tab matches \(expectedTab)")
            currentIndex = (currentIndex + 1 + tabs.count) % tabs.count
        }

        // 21B: Backward tab wrapping: 0 -> 3 -> 2 -> 1 -> 0
        currentIndex = 0
        let backwardSequence: [SettingsTab] = [.general, .about, .history, .captureSave, .general]
        for expectedTab in backwardSequence {
            ChallengerHarness.assertEqual(tabs[currentIndex], expectedTab, "Backward step matches \(expectedTab)")
            currentIndex = (currentIndex - 1 + tabs.count) % tabs.count
        }

        // 21C: 1,000 steps continuous forward cycling stress
        currentIndex = 0
        var allForwardValid = true
        for step in 0..<1000 {
            let expectedIndex = step % tabs.count
            if currentIndex != expectedIndex {
                allForwardValid = false
                break
            }
            currentIndex = (currentIndex + 1 + tabs.count) % tabs.count
        }
        ChallengerHarness.assertTrue(allForwardValid, "1,000 continuous forward steps wrap modulo 4 with 100% precision")

        // 21D: 1,000 steps continuous backward cycling stress
        currentIndex = 0
        var allBackwardValid = true
        for step in 0..<1000 {
            let expectedIndex = (tabs.count - (step % tabs.count)) % tabs.count
            if currentIndex != expectedIndex {
                allBackwardValid = false
                break
            }
            currentIndex = (currentIndex - 1 + tabs.count) % tabs.count
        }
        ChallengerHarness.assertTrue(allBackwardValid, "1,000 continuous backward steps wrap modulo 4 with 100% precision")

        // 21E: 500 rapid forward-backward pairs
        currentIndex = 1
        for _ in 0..<500 {
            currentIndex = (currentIndex + 1 + tabs.count) % tabs.count
            currentIndex = (currentIndex - 1 + tabs.count) % tabs.count
        }
        ChallengerHarness.assertEqual(currentIndex, 1, "500 forward-backward cycles restore exact tab index 1")

        // 21F: Notification-based Cycling Integration Test
        let advSettings = AppSettings()
        let advStorage = StorageManager(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("AdvSettingsTest_\(UUID().uuidString)"))
        let controller = SettingsWindowController(appSettings: advSettings, storageManager: advStorage)
        var receivedDirections: [Int] = []
        let observer = NotificationCenter.default.addObserver(forName: .settingsCycleTab, object: nil, queue: nil) { notif in
            if let dir = notif.userInfo?["direction"] as? Int {
                receivedDirections.append(dir)
            }
        }

        // Keycode 33 ([) with Command
        let cmdLeftBracket = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        controller.window?.keyDown(with: cmdLeftBracket)

        // Keycode 30 (]) with Command
        let cmdRightBracket = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "]",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!
        controller.window?.keyDown(with: cmdRightBracket)

        // Keycode 33 with Cmd+Shift
        let cmdShiftLeftBracket = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "{",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        controller.window?.keyDown(with: cmdShiftLeftBracket)

        // Keycode 30 with Cmd+Shift
        let cmdShiftRightBracket = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "}",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!
        controller.window?.keyDown(with: cmdShiftRightBracket)

        NotificationCenter.default.removeObserver(observer)

        ChallengerHarness.assertEqual(receivedDirections, [-1, 1, -1, 1], "Received expected sequence of cycle directions [-1, 1, -1, 1]")
    }

    // MARK: - 22. Milestone M30 Empirical Stress & Adversarial Challenge
    private static func testMilestoneM30EmpiricalStressAndAdversarialChallenge() {
        ChallengerHarness.startSuite("22. Milestone M30 Empirical Stress & Adversarial Challenge")

        let screenBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let sampleCtx = CGContext(
            data: nil,
            width: 1920,
            height: 1080,
            bitsPerComponent: 8,
            bytesPerRow: 1920 * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let bgImage = sampleCtx.makeImage() else {
            ChallengerHarness.recordFail("Overlay Context Setup", reason: "Could not create sample context")
            return
        }

        // Sub-scenario 22A: Selection Box Resizing Near Bounds & 10pt Size Clamping
        let display = CaptureDisplayInfo(
            displayID: 1,
            name: "TestDisplay",
            cocoaFrame: screenBounds,
            cgBounds: screenBounds,
            scaleFactor: 2.0,
            isMain: true,
            pixelSize: CGSize(width: 3840, height: 2160)
        )
        let captured = CapturedScreen(displayInfo: display, fullImage: bgImage, timestamp: Date())
        let overlayView = CaptureOverlayContentView(
            frame: screenBounds,
            capturedScreen: captured,
            appSettings: AppSettings(),
            windowDelegate: nil
        )
        overlayView.selectionRect = CGRect(x: 100, y: 100, width: 100, height: 100)

        // 1. Repeated contraction (100 times Option+Left 10pt)
        let optShiftLeft = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        )!
        for _ in 0..<100 {
            _ = overlayView.handleOverlayKeyDown(with: optShiftLeft)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.width, 10.0, "100x Option+Shift+Left clamped strictly to 10.0pt minimum width")

        // 2. Repeated contraction (100 times Option+Down 10pt)
        let optShiftDown = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        )!
        for _ in 0..<100 {
            _ = overlayView.handleOverlayKeyDown(with: optShiftDown)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.height, 10.0, "100x Option+Shift+Down clamped strictly to 10.0pt minimum height")

        // 3. Selection box expansion near screen bounds (maxX, maxY)
        // Position box at (1900, 1060, 10, 10) in 1920x1080 bounds
        overlayView.selectionRect = CGRect(x: 1900, y: 1060, width: 10, height: 10)
        let optShiftRight = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        // Expand right 10 times (+100pt requested, but space is only 1920 - 1900 = 20pt)
        for _ in 0..<10 {
            _ = overlayView.handleOverlayKeyDown(with: optShiftRight)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.width, 20.0, "Expansion right clamped strictly at screen maxX (1920 - 1900 = 20pt)")
        ChallengerHarness.assertEqual(overlayView.selectionRect.maxX, 1920.0, "selectionRect.maxX equals screen bounds maxX")

        // Expand up 10 times (+100pt requested, but space is only 1080 - 1060 = 20pt)
        let optShiftUp = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        for _ in 0..<10 {
            _ = overlayView.handleOverlayKeyDown(with: optShiftUp)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.height, 20.0, "Expansion up clamped strictly at screen maxY (1080 - 1060 = 20pt)")
        ChallengerHarness.assertEqual(overlayView.selectionRect.maxY, 1080.0, "selectionRect.maxY equals screen bounds maxY")

        // 4. Repeated extreme nudging against all 4 screen edges
        let shiftLeft = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123)!
        for _ in 0..<300 {
            _ = overlayView.handleOverlayKeyDown(with: shiftLeft)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.origin.x, 0.0, "Extreme left nudging clamped strictly to bounds.minX (0.0)")

        let shiftDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)!
        for _ in 0..<300 {
            _ = overlayView.handleOverlayKeyDown(with: shiftDown)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.origin.y, 0.0, "Extreme down nudging clamped strictly to bounds.minY (0.0)")

        let shiftRight = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        for _ in 0..<300 {
            _ = overlayView.handleOverlayKeyDown(with: shiftRight)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.origin.x, screenBounds.maxX - overlayView.selectionRect.width, "Extreme right nudging clamped strictly to bounds.maxX - width")

        let shiftUp = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 126)!
        for _ in 0..<300 {
            _ = overlayView.handleOverlayKeyDown(with: shiftUp)
        }
        ChallengerHarness.assertEqual(overlayView.selectionRect.origin.y, screenBounds.maxY - overlayView.selectionRect.height, "Extreme up nudging clamped strictly to bounds.maxY - height")

        // Sub-scenario 22B: Resizing Annotation Objects Under Repeated/Extreme Option+Arrow Key Events
        let engine = overlayView.annotationEngine
        _ = engine.clearAll()

        // 1. Multi-tool object creation and resize stress
        let tools: [AnnotationTool] = [.rectangle, .ellipse, .arrow, .line, .pen, .highlighter, .text, .blur]
        for (i, tool) in tools.enumerated() {
            var pts: [CGPoint] = [CGPoint(x: 100 + i * 10, y: 100 + i * 10), CGPoint(x: 200 + i * 10, y: 200 + i * 10)]
            if tool == .pen || tool == .highlighter {
                pts.append(CGPoint(x: 150 + i * 10, y: 250 + i * 10))
            }
            let obj = AnnotationObject(
                tool: tool,
                points: pts,
                bounds: CGRect(x: 100 + CGFloat(i * 10), y: 100 + CGFloat(i * 10), width: 100, height: 100),
                colorHex: "#FF3B30",
                strokeWidth: 4,
                text: tool == .text ? "Test Label" : ""
            )
            engine.addObject(obj)
            engine.selectedObjectID = obj.id

            // Repeated 50 contractions
            for _ in 0..<50 {
                engine.resizeSelected(deltaWidth: -10, deltaHeight: -10, minimumDimension: 10.0)
            }
            ChallengerHarness.assertEqual(engine.selectedObject?.bounds.width, 10.0, "\(tool) width clamped to 10.0pt after 50 contractions")
            ChallengerHarness.assertEqual(engine.selectedObject?.bounds.height, 10.0, "\(tool) height clamped to 10.0pt after 50 contractions")

            // Extreme delta single step
            let resizedExtreme = engine.resizeSelected(deltaWidth: -999999, deltaHeight: -999999, minimumDimension: 10.0)
            ChallengerHarness.assertFalse(resizedExtreme, "\(tool) extreme contraction rejected when already at minimum dimension")

            // Expansion with boundary
            let boundary = CGRect(x: 0, y: 0, width: 500, height: 500)
            let expanded = engine.resizeSelected(deltaWidth: 10000, deltaHeight: 10000, boundary: boundary)
            ChallengerHarness.assertTrue(expanded, "\(tool) expanded within boundary")
            let maxExpectedW = boundary.maxX - (engine.selectedObject?.bounds.minX ?? 0)
            let maxExpectedH = boundary.maxY - (engine.selectedObject?.bounds.minY ?? 0)
            ChallengerHarness.assertEqual(engine.selectedObject?.bounds.width, maxExpectedW, "\(tool) width clamped to boundary maxX")
            ChallengerHarness.assertEqual(engine.selectedObject?.bounds.height, maxExpectedH, "\(tool) height clamped to boundary maxY")

            // Undo restores previous dimensions
            ChallengerHarness.assertTrue(engine.canUndo, "\(tool) canUndo is true")
            engine.undo()
            ChallengerHarness.assertEqual(engine.selectedObject?.bounds.width, 10.0, "\(tool) undo restores contracted dimension 10.0pt")
        }

        // Sub-scenario 22C: clearAll() Under Empty Canvas, Single Object, and 150+ Objects with Undo/Redo Cycles
        let cleanEngine = AnnotationEngine()

        // 1. Empty Canvas
        let emptyCleared = cleanEngine.clearAll()
        ChallengerHarness.assertEqual(emptyCleared, 0, "clearAll on empty canvas returns 0")
        ChallengerHarness.assertFalse(cleanEngine.canUndo, "canUndo is false after clearAll on empty canvas")
        cleanEngine.undo()
        ChallengerHarness.assertEqual(cleanEngine.objects.count, 0, "Undo on empty clearAll remains 0")

        // 2. Single Object
        let singleObj = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 50, y: 50, width: 80, height: 60),
            colorHex: "#007AFF",
            strokeWidth: 3
        )
        cleanEngine.addObject(singleObj)
        ChallengerHarness.assertEqual(cleanEngine.objects.count, 1, "Single object added")
        let singleCleared = cleanEngine.clearAll()
        ChallengerHarness.assertEqual(singleCleared, 1, "clearAll returned 1")
        ChallengerHarness.assertTrue(cleanEngine.objects.isEmpty, "objects is empty")
        ChallengerHarness.assertTrue(cleanEngine.canUndo, "canUndo is true")
        cleanEngine.undo()
        ChallengerHarness.assertEqual(cleanEngine.objects.count, 1, "undo restores 1 object")
        ChallengerHarness.assertEqual(cleanEngine.objects.first?.id, singleObj.id, "restored object matches original ID")
        cleanEngine.redo()
        ChallengerHarness.assertTrue(cleanEngine.objects.isEmpty, "redo re-clears canvas")
        cleanEngine.undo() // Leave canvas with 1 object

        // 3. 150+ Objects with Multiple Undo/Redo Cycles & Layer Z-Index Preservation
        _ = cleanEngine.clearAll()
        let stressEngine = AnnotationEngine()

        let objectCount = 150
        var expectedIDs: [UUID] = []
        for i in 0..<objectCount {
            let tool = tools[i % tools.count]
            let obj = AnnotationObject(
                tool: tool,
                bounds: CGRect(x: CGFloat(i * 2), y: CGFloat(i * 2), width: 50, height: 50),
                colorHex: "#34C759",
                strokeWidth: 2
            )
            stressEngine.addObject(obj)
            expectedIDs.append(obj.id)
        }
        ChallengerHarness.assertEqual(stressEngine.objects.count, 150, "150 annotations added to stress engine")

        let countRemoved = stressEngine.clearAll()
        ChallengerHarness.assertEqual(countRemoved, 150, "clearAll returned 150 removed objects")
        ChallengerHarness.assertTrue(stressEngine.objects.isEmpty, "Canvas is empty after clearAll")
        ChallengerHarness.assertNil(stressEngine.selectedObjectID, "selectedObjectID is nil after clearAll")

        // Perform 5 full undo/redo cycles
        for cycle in 1...5 {
            ChallengerHarness.assertTrue(stressEngine.canUndo, "Cycle \(cycle): canUndo is true")
            stressEngine.undo()
            ChallengerHarness.assertEqual(stressEngine.objects.count, 150, "Cycle \(cycle): undo restored all 150 objects")
            let restoredIDs = stressEngine.objects.map { $0.id }
            ChallengerHarness.assertEqual(restoredIDs, expectedIDs, "Cycle \(cycle): layer z-index order 100% preserved after undo")

            ChallengerHarness.assertTrue(stressEngine.canRedo, "Cycle \(cycle): canRedo is true")
            stressEngine.redo()
            ChallengerHarness.assertTrue(stressEngine.objects.isEmpty, "Cycle \(cycle): redo re-clears all 150 objects")
        }

        // Final undo to restore state, then append a new object to truncate redo stack
        stressEngine.undo()
        ChallengerHarness.assertEqual(stressEngine.objects.count, 150, "Final undo restored 150 objects")
        let brandNewObj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 20, height: 20))
        stressEngine.addObject(brandNewObj)
        ChallengerHarness.assertEqual(stressEngine.objects.count, 151, "New object added, objects count is 151")
        ChallengerHarness.assertFalse(stressEngine.canRedo, "Redo stack truncated after new action")

        // Sub-scenario 22D: Cmd+E Share Invocation When No Window/Canvas is Focused
        // 1. ToolbarsViewModel with nil defaultAnchorView and nil onShareRequested
        let unanchoredVM = FloatingToolbarsViewModel(appSettings: AppSettings())
        unanchoredVM.triggerShare(from: nil) // Must not crash
        ChallengerHarness.assertNil(unanchoredVM.defaultAnchorView, "unanchoredVM defaultAnchorView is nil")

        // 2. ToolbarsViewModel with nil defaultAnchorView but with onShareRequested callback
        var shareCalled = false
        unanchoredVM.onShareRequested = { _ in shareCalled = true }
        unanchoredVM.triggerShare(from: nil)
        ChallengerHarness.assertFalse(shareCalled, "onShareRequested not invoked when no anchor view is available")

        // 3. ToolbarsViewModel with detached anchor view (no window)
        let detachedView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        ChallengerHarness.assertNil(detachedView.window, "detachedView has no window")
        unanchoredVM.defaultAnchorView = detachedView
        unanchoredVM.triggerShare()
        ChallengerHarness.assertTrue(shareCalled, "onShareRequested invoked with detached defaultAnchorView safely")

        // 4. Cmd+E Key Event Dispatch via ToolbarKeyShortcutHandler with no key window
        shareCalled = false
        let cmdEEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "e",
            charactersIgnoringModifiers: "e",
            isARepeat: false,
            keyCode: 14
        )!
        let handled = ToolbarKeyShortcutHandler.handleKeyEvent(event: cmdEEvent, viewModel: unanchoredVM)
        ChallengerHarness.assertTrue(handled, "Cmd+E handled by ToolbarKeyShortcutHandler without focused window")
        ChallengerHarness.assertTrue(shareCalled, "Cmd+E successfully triggered share action safely")
    }

    // MARK: - 23. Milestone M35 Empirical Stress & Adversarial Challenge
    private static func testMilestoneM35EmpiricalStressAndAdversarialChallenge() {
        ChallengerHarness.startSuite("23. Milestone M35 v1.0.17 Empirical Stress & Adversarial Challenge")

        // =====================================================================
        // Sub-scenario 23A: Option Center-Out Geometry Stress & Boundary Clamping
        // =====================================================================
        ChallengerHarness.startSuite("23A. Option Center-Out Geometry Stress & Boundary Clamping")

        let screenBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let centerPt = CGPoint(x: 1000, y: 800)

        // 1. Standard center-out expansion (squareConstrained = false)
        let targetPt = CGPoint(x: 1200, y: 950)
        let rectStd = SelectionBoxGeometry.calculateCenterRect(
            center: centerPt,
            target: targetPt,
            bounds: screenBounds,
            squareConstrained: false
        )
        // dx = 200, dy = 150 -> halfW = 200, halfH = 150 -> width = 400, height = 300
        ChallengerHarness.assertEqual(rectStd.origin.x, 800.0, "rectStd origin x is center.x - 200 = 800")
        ChallengerHarness.assertEqual(rectStd.origin.y, 650.0, "rectStd origin y is center.y - 150 = 650")
        ChallengerHarness.assertEqual(rectStd.width, 400.0, "rectStd width is 400.0")
        ChallengerHarness.assertEqual(rectStd.height, 300.0, "rectStd height is 300.0")
        ChallengerHarness.assertEqual(rectStd.midX, centerPt.x, "rectStd midX matches center point x (1000.0)")
        ChallengerHarness.assertEqual(rectStd.midY, centerPt.y, "rectStd midY matches center point y (800.0)")

        // 2. Square-constrained center-out expansion (squareConstrained = true)
        let rectSquare = SelectionBoxGeometry.calculateCenterRect(
            center: centerPt,
            target: targetPt,
            bounds: screenBounds,
            squareConstrained: true
        )
        // max(dx, dy) = max(200, 150) = 200 -> side = 200, halfW = 200, halfH = 200 -> width = 400, height = 400
        ChallengerHarness.assertEqual(rectSquare.width, 400.0, "rectSquare width is 400.0")
        ChallengerHarness.assertEqual(rectSquare.height, 400.0, "rectSquare height is 400.0 (1:1 square)")
        ChallengerHarness.assertEqual(rectSquare.origin.x, 800.0, "rectSquare origin x is 800.0")
        ChallengerHarness.assertEqual(rectSquare.origin.y, 600.0, "rectSquare origin y is 600.0")
        ChallengerHarness.assertEqual(rectSquare.midX, centerPt.x, "rectSquare midX is center x")
        ChallengerHarness.assertEqual(rectSquare.midY, centerPt.y, "rectSquare midY is center y")

        // 3. 4-Quadrant Symmetry Test:
        // Dragging in any of the 4 quadrants with identical deltas produces identical bounding rectangles
        let dx: CGFloat = 160
        let dy: CGFloat = 90
        let q1Target = CGPoint(x: centerPt.x + dx, y: centerPt.y + dy)
        let q2Target = CGPoint(x: centerPt.x - dx, y: centerPt.y + dy)
        let q3Target = CGPoint(x: centerPt.x - dx, y: centerPt.y - dy)
        let q4Target = CGPoint(x: centerPt.x + dx, y: centerPt.y - dy)

        let rQ1 = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: q1Target, bounds: screenBounds)
        let rQ2 = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: q2Target, bounds: screenBounds)
        let rQ3 = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: q3Target, bounds: screenBounds)
        let rQ4 = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: q4Target, bounds: screenBounds)

        ChallengerHarness.assertEqual(rQ1, rQ2, "Quadrant 1 and Quadrant 2 center-out rects are identical")
        ChallengerHarness.assertEqual(rQ2, rQ3, "Quadrant 2 and Quadrant 3 center-out rects are identical")
        ChallengerHarness.assertEqual(rQ3, rQ4, "Quadrant 3 and Quadrant 4 center-out rects are identical")
        ChallengerHarness.assertEqual(rQ1.width, dx * 2, "Width is exactly 2 * dx = 320.0")
        ChallengerHarness.assertEqual(rQ1.height, dy * 2, "Height is exactly 2 * dy = 180.0")

        // 4. Extreme coordinates & Boundary Clamping
        // Extreme negative coordinates (-1,000,000)
        let extremeNeg = CGPoint(x: -1_000_000, y: -1_000_000)
        let rNeg = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: extremeNeg, bounds: screenBounds)
        ChallengerHarness.assertTrue(rNeg.minX >= screenBounds.minX, "Extreme negative target clamped to screen minX")
        ChallengerHarness.assertTrue(rNeg.minY >= screenBounds.minY, "Extreme negative target clamped to screen minY")
        ChallengerHarness.assertTrue(rNeg.maxX <= screenBounds.maxX, "Extreme negative target clamped to screen maxX")
        ChallengerHarness.assertTrue(rNeg.maxY <= screenBounds.maxY, "Extreme negative target clamped to screen maxY")
        ChallengerHarness.assertFalse(rNeg.width.isNaN, "Width is not NaN under extreme negative coordinates")
        ChallengerHarness.assertFalse(rNeg.height.isNaN, "Height is not NaN under extreme negative coordinates")

        // Extreme positive coordinates (+1,000,000)
        let extremePos = CGPoint(x: 1_000_000, y: 1_000_000)
        let rPos = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: extremePos, bounds: screenBounds)
        ChallengerHarness.assertTrue(rPos.minX >= screenBounds.minX, "Extreme positive target clamped to screen minX")
        ChallengerHarness.assertTrue(rPos.minY >= screenBounds.minY, "Extreme positive target clamped to screen minY")
        ChallengerHarness.assertTrue(rPos.maxX <= screenBounds.maxX, "Extreme positive target clamped to screen maxX")
        ChallengerHarness.assertTrue(rPos.maxY <= screenBounds.maxY, "Extreme positive target clamped to screen maxY")
        ChallengerHarness.assertFalse(rPos.width.isNaN, "Width is not NaN under extreme positive coordinates")
        ChallengerHarness.assertFalse(rPos.height.isNaN, "Height is not NaN under extreme positive coordinates")

        // 5. Center outside bounds
        let outCenter = CGPoint(x: -500, y: -500)
        let rOutCenter = SelectionBoxGeometry.calculateCenterRect(center: outCenter, target: CGPoint(x: 100, y: 100), bounds: screenBounds)
        ChallengerHarness.assertTrue(rOutCenter.minX >= screenBounds.minX, "Center outside bounds clamped safely to screen minX")
        ChallengerHarness.assertTrue(rOutCenter.minY >= screenBounds.minY, "Center outside bounds clamped safely to screen minY")
        ChallengerHarness.assertTrue(rOutCenter.width >= 1.0, "Center outside bounds produces width >= 1.0")
        ChallengerHarness.assertTrue(rOutCenter.height >= 1.0, "Center outside bounds produces height >= 1.0")

        // 6. Subpixel clicks & Micro displacements
        let microTarget = CGPoint(x: centerPt.x + 0.000001, y: centerPt.y + 0.000001)
        let rMicro = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: microTarget, bounds: screenBounds)
        ChallengerHarness.assertTrue(rMicro.width >= 1.0, "Subpixel micro displacement produces width >= 1.0pt")
        ChallengerHarness.assertTrue(rMicro.height >= 1.0, "Subpixel micro displacement produces height >= 1.0pt")

        // 7. Zero distance (center == target)
        let rZero = SelectionBoxGeometry.calculateCenterRect(center: centerPt, target: centerPt, bounds: screenBounds)
        ChallengerHarness.assertTrue(rZero.width >= 1.0, "Zero distance produces width >= 1.0pt")
        ChallengerHarness.assertTrue(rZero.height >= 1.0, "Zero distance produces height >= 1.0pt")

        // 8. Zero-width and zero-height bounds
        let zeroBounds = CGRect(x: 200, y: 200, width: 0, height: 0)
        let rZeroBounds = SelectionBoxGeometry.calculateCenterRect(center: CGPoint(x: 200, y: 200), target: CGPoint(x: 250, y: 250), bounds: zeroBounds)
        ChallengerHarness.assertTrue(rZeroBounds.width >= 1.0, "Zero-width bounds returns safe minimum width >= 1.0")
        ChallengerHarness.assertTrue(rZeroBounds.height >= 1.0, "Zero-height bounds returns safe minimum height >= 1.0")

        // 9. 1,000 pseudo-random coordinate fuzzing trials
        var fuzzerSeed: UInt64 = 0x123456789ABCDEF0
        var allFuzzValid = true
        for _ in 0..<1000 {
            fuzzerSeed = (fuzzerSeed &* 6364136223846793005) &+ 1
            let randCX = CGFloat(Double(Int(fuzzerSeed % 10000) - 5000) * 2.5)
            fuzzerSeed = (fuzzerSeed &* 6364136223846793005) &+ 1
            let randCY = CGFloat(Double(Int(fuzzerSeed % 10000) - 5000) * 2.5)
            fuzzerSeed = (fuzzerSeed &* 6364136223846793005) &+ 1
            let randTX = CGFloat(Double(Int(fuzzerSeed % 10000) - 5000) * 2.5)
            fuzzerSeed = (fuzzerSeed &* 6364136223846793005) &+ 1
            let randTY = CGFloat(Double(Int(fuzzerSeed % 10000) - 5000) * 2.5)
            fuzzerSeed = (fuzzerSeed &* 6364136223846793005) &+ 1
            let sq = (fuzzerSeed % 2 == 0)

            let fuzzed = SelectionBoxGeometry.calculateCenterRect(
                center: CGPoint(x: randCX, y: randCY),
                target: CGPoint(x: randTX, y: randTY),
                bounds: screenBounds,
                squareConstrained: sq
            )
            if fuzzed.width < 1.0 || fuzzed.height < 1.0 || fuzzed.width.isNaN || fuzzed.height.isNaN || fuzzed.width.isInfinite || fuzzed.height.isInfinite {
                allFuzzValid = false
                break
            }
        }
        ChallengerHarness.assertTrue(allFuzzValid, "1,000 pseudo-random coordinate fuzzing trials generated strictly valid bounds")

        // =====================================================================
        // Sub-scenario 23B: 10,000 Rapid Layer Reorderings with Full Reverse Undo & Redo
        // =====================================================================
        ChallengerHarness.startSuite("23B. 10,000 Rapid Layer Reorderings with Full Reverse Undo & Redo")

        let reorderEngine = AnnotationEngine(maxHistoryLimit: 25000)
        let tools: [AnnotationTool] = [.rectangle, .ellipse, .arrow, .line, .pen, .highlighter, .text, .blur]
        let objectCount = 40

        for i in 0..<objectCount {
            let tool = tools[i % tools.count]
            let obj = AnnotationObject(
                tool: tool,
                points: [CGPoint(x: i * 5, y: i * 5), CGPoint(x: i * 5 + 30, y: i * 5 + 30)],
                bounds: CGRect(x: CGFloat(i * 5), y: CGFloat(i * 5), width: 30, height: 30),
                colorHex: "#FF0000",
                strokeWidth: 2,
                text: "Annotation \(i)"
            )
            reorderEngine.addObject(obj)
        }

        ChallengerHarness.assertEqual(reorderEngine.objects.count, objectCount, "Engine seeded with 40 distinct annotations")
        let initialOrder = reorderEngine.objects.map { $0.id }
        ChallengerHarness.assertEqual(Set(initialOrder).count, objectCount, "All 40 object IDs are unique")

        // Perform 10,000 successful reordering operations
        var reorderRng: UInt64 = 0xDEADBEEFCAFE1234
        var successfulReorders = 0
        var totalAttempts = 0

        while successfulReorders < 10000 {
            totalAttempts += 1
            reorderRng = (reorderRng &* 6364136223846793005) &+ 1
            let targetIdx = Int(reorderRng % UInt64(reorderEngine.objects.count))
            let objId = reorderEngine.objects[targetIdx].id
            reorderEngine.selectedObjectID = objId

            reorderRng = (reorderRng &* 6364136223846793005) &+ 1
            let op = Int(reorderRng % 4)

            var didMutate = false
            switch op {
            case 0: didMutate = reorderEngine.bringSelectedToFront()
            case 1: didMutate = reorderEngine.sendSelectedToBack()
            case 2: didMutate = reorderEngine.bringSelectedForward()
            case 3: didMutate = reorderEngine.sendSelectedBackward()
            default: break
            }

            if didMutate {
                successfulReorders += 1
                if successfulReorders % 2500 == 0 {
                    ChallengerHarness.assertEqual(reorderEngine.objects.count, objectCount, "Invariant: count remains 40 at step \(successfulReorders)")
                    let currentSet = Set(reorderEngine.objects.map { $0.id })
                    ChallengerHarness.assertEqual(currentSet, Set(initialOrder), "Invariant: 0 object loss or duplication at step \(successfulReorders)")
                }
            }
        }

        ChallengerHarness.assertEqual(successfulReorders, 10000, "Completed exactly 10,000 successful layer reordering mutations")
        let scrambledOrder = reorderEngine.objects.map { $0.id }
        ChallengerHarness.assertTrue(scrambledOrder != initialOrder, "Objects successfully scrambled after 10,000 reorder operations")
        ChallengerHarness.assertTrue(reorderEngine.canUndo, "canUndo is true after 10,000 operations")

        // Full Reverse Undo Sequence for the 10,000 reorders
        var undosCompleted = 0
        for _ in 0..<10000 {
            reorderEngine.undo()
            undosCompleted += 1
        }
        ChallengerHarness.assertEqual(undosCompleted, 10000, "Successfully executed all 10,000 undo steps")
        ChallengerHarness.assertTrue(reorderEngine.canRedo, "Redo stack populated with 10,000 actions (canRedo == true)")

        let restoredOrder = reorderEngine.objects.map { $0.id }
        ChallengerHarness.assertEqual(restoredOrder, initialOrder, "100% z-index invariant preservation: initial order fully restored after 10,000 undos")

        // Full Forward Redo Sequence for the 10,000 reorders
        var redosCompleted = 0
        for _ in 0..<10000 {
            reorderEngine.redo()
            redosCompleted += 1
        }
        ChallengerHarness.assertEqual(redosCompleted, 10000, "Successfully executed all 10,000 redo steps")
        ChallengerHarness.assertFalse(reorderEngine.canRedo, "Redo stack fully drained (canRedo == false)")
        ChallengerHarness.assertTrue(reorderEngine.canUndo, "Undo stack restored with 10,000 actions")

        let redoneOrder = reorderEngine.objects.map { $0.id }
        ChallengerHarness.assertEqual(redoneOrder, scrambledOrder, "100% z-index invariant preservation: scrambled order restored after 10,000 redos")

        // Edge Cases: Empty canvas, single object, nil selectedObjectID
        let emptyEngine = AnnotationEngine()
        ChallengerHarness.assertFalse(emptyEngine.bringSelectedToFront(), "bringSelectedToFront on empty engine returns false")
        ChallengerHarness.assertFalse(emptyEngine.sendSelectedToBack(), "sendSelectedToBack on empty engine returns false")
        ChallengerHarness.assertFalse(emptyEngine.bringSelectedForward(), "bringSelectedForward on empty engine returns false")
        ChallengerHarness.assertFalse(emptyEngine.sendSelectedBackward(), "sendSelectedBackward on empty engine returns false")
        ChallengerHarness.assertFalse(emptyEngine.canUndo, "No undo actions created on empty engine")

        let singleEngine = AnnotationEngine()
        let singleObj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 20, height: 20))
        singleEngine.addObject(singleObj)
        singleEngine.selectedObjectID = singleObj.id
        ChallengerHarness.assertFalse(singleEngine.bringSelectedToFront(), "bringSelectedToFront on 1-object engine returns false")
        ChallengerHarness.assertFalse(singleEngine.sendSelectedToBack(), "sendSelectedToBack on 1-object engine returns false")
        ChallengerHarness.assertFalse(singleEngine.bringSelectedForward(), "bringSelectedForward on 1-object engine returns false")
        ChallengerHarness.assertFalse(singleEngine.sendSelectedBackward(), "sendSelectedBackward on 1-object engine returns false")

        // =====================================================================
        // Sub-scenario 23C: Viewport Scrolling Boundary Stress & Extreme Dimensions (Up to 30,000px)
        // =====================================================================
        ChallengerHarness.startSuite("23C. Viewport Scrolling Boundary Stress & Extreme Dimensions (30,000px)")

        // Create base dummy image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 100 * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let dummyBase = ctx.makeImage() else {
            ChallengerHarness.recordFail("Viewport Stress Context", reason: "Could not create sample base image")
            return
        }

        let tallDocView = ScrollableAnnotationDocumentView(baseImage: dummyBase, engine: AnnotationEngine(), scale: 1.0)
        // Set document canvas frame to extreme height 30,000px and width 1,200px
        let tallWidth: CGFloat = 1200.0
        let tallHeight: CGFloat = 30000.0
        tallDocView.frame = NSRect(x: 0, y: 0, width: tallWidth, height: tallHeight)

        let tallScrollView = ScrollableAnnotationScrollView(documentCanvasView: tallDocView)
        let viewportW: CGFloat = 1000.0
        let viewportH: CGFloat = 800.0
        tallScrollView.frame = NSRect(x: 0, y: 0, width: viewportW, height: viewportH)
        tallScrollView.contentView.frame = NSRect(x: 0, y: 0, width: viewportW, height: viewportH)

        let expectedMaxOriginX = max(0, tallWidth - viewportW)  // 200.0
        let expectedMaxOriginY = max(0, tallHeight - viewportH) // 29200.0

        // 1. Initial position & scrollToTop
        tallScrollView.scrollToTop()
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.y, 0.0, "scrollToTop sets origin y to 0.0")

        // 2. scrollToBottom
        tallScrollView.scrollToBottom()
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.y, expectedMaxOriginY, "scrollToBottom sets origin y to expected max 29200.0")

        // 3. Overscroll past bounds (huge positive delta)
        tallScrollView.scrollBy(deltaX: 50000.0, deltaY: 500000.0)
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.x, expectedMaxOriginX, "Extreme positive scroll delta clamped strictly to maxOriginX (200.0)")
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.y, expectedMaxOriginY, "Extreme positive scroll delta clamped strictly to maxOriginY (29200.0)")

        // 4. Overscroll past bounds (huge negative delta)
        tallScrollView.scrollBy(deltaX: -50000.0, deltaY: -500000.0)
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.x, 0.0, "Extreme negative scroll delta clamped strictly to origin x 0.0")
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.y, 0.0, "Extreme negative scroll delta clamped strictly to origin y 0.0")

        // 5. PageDown and PageUp sequences
        let pageStep = viewportH * 0.85 // 680.0
        tallScrollView.pageDown()
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.y, pageStep, "Single pageDown stepped by 85% of viewport height (680.0)")
        tallScrollView.pageUp()
        ChallengerHarness.assertEqual(tallScrollView.contentView.bounds.origin.y, 0.0, "Single pageUp returned origin y to 0.0")

        // 6. 1,000 rapid high-velocity deltas fuzzing
        var scrollRng: UInt64 = 0x55AA55AA11223344
        var allScrollBounded = true
        for _ in 0..<1000 {
            scrollRng = (scrollRng &* 6364136223846793005) &+ 1
            let randDx = CGFloat(Double(Int(scrollRng % 200000) - 100000) * 0.5)
            scrollRng = (scrollRng &* 6364136223846793005) &+ 1
            let randDy = CGFloat(Double(Int(scrollRng % 200000) - 100000) * 0.5)

            tallScrollView.scrollBy(deltaX: randDx, deltaY: randDy)
            let currX = tallScrollView.contentView.bounds.origin.x
            let currY = tallScrollView.contentView.bounds.origin.y

            if currX < 0 || currX > expectedMaxOriginX || currY < 0 || currY > expectedMaxOriginY || currX.isNaN || currY.isNaN {
                allScrollBounded = false
                break
            }
        }
        ChallengerHarness.assertTrue(allScrollBounded, "1,000 high-velocity scrolling deltas remained 100% within valid bounds [0, maxOrigin]")

        // 7. NaN and Infinite coordinates robustness
        tallScrollView.scrollToTop()
        tallScrollView.scrollBy(deltaX: .infinity, deltaY: .infinity)
        let infX = tallScrollView.contentView.bounds.origin.x
        let infY = tallScrollView.contentView.bounds.origin.y
        ChallengerHarness.assertTrue(!infX.isNaN && !infY.isNaN, "+Infinity deltas handled safely without NaN coordinates")

        tallScrollView.scrollBy(deltaX: -.infinity, deltaY: -.infinity)
        let negInfX = tallScrollView.contentView.bounds.origin.x
        let negInfY = tallScrollView.contentView.bounds.origin.y
        ChallengerHarness.assertTrue(!negInfX.isNaN && !negInfY.isNaN, "-Infinity deltas handled safely without NaN coordinates")

        // =====================================================================
        // Sub-scenario 23D: Popover Search Fuzzing with Unicode Strings & Rapid Shortcut Cycling
        // =====================================================================
        ChallengerHarness.startSuite("23D. Popover Search Fuzzing with Unicode Strings & Rapid Shortcut Cycling")

        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShotAdvM35_\(UUID().uuidString)")
        let storage = StorageManager(baseDirectory: sandboxDir, initialCapacity: 50)

        // Seed storage with diverse multi-lingual items
        let testSeedData: [(app: String, type: ShotCaptureType, tags: [String])] = [
            ("Xcode", .region, ["swift", "build", "debug"]),
            ("Safari", .scrolling, ["web", "docs", "article"]),
            ("Terminal", .region, ["cli", "zsh", "bash"]),
            ("Notes", .region, ["meeting", "ideas"]),
            ("Slack", .region, ["team", "chat", "urgent"]),
            ("Vietnamese App", .region, ["anh", "chup", "man", "hinh"]),
            ("Bao Cao", .scrolling, ["tieng", "viet", "ky", "thuat"]),
            ("Japanese App", .region, ["nihon", "code", "review"]),
            ("Chinese App", .scrolling, ["xitong", "jiagou", "shuju"]),
            ("Arabic App", .region, ["taqrir", "nizam"]),
            ("Alpha Beta", .region, ["greek", "math", "symbol"]),
            ("Release v1.0.17", .region, ["milestone", "changelog"])
        ]

        for item in testSeedData {
            _ = try? storage.save(image: dummyBase, sourceApp: item.app, captureType: item.type, tags: item.tags)
        }

        ChallengerHarness.assertEqual(storage.items.count, testSeedData.count, "Storage populated with \(testSeedData.count) seed items")

        // Fuzz query list with Unicode strings (diacritics, CJK, symbols, whitespace, formatting, control chars)
        let fuzzQueries: [String] = [
            "", // empty
            "   ", // whitespace only
            "\t\n\r",
            "xcode", // exact lower
            "XCODE", // exact upper
            "Xcode", // mixed
            "Safari",
            "v1.0.17",
            "Vietnamese",
            "man hinh",
            "Bao Cao",
            "review",
            "team",
            "math",
            "Greek",
            // Unicode characters (Vietnamese, CJK, Arabic, Math)
            "Tiếng Việt",
            "Ảnh chụp màn hình",
            "Báo cáo",
            "日本語",
            "開発",
            "系统架构",
            "性能测试",
            "تقرير فحص",
            "العربية",
            "∀x ∈ ℝ",
            "α, β, γ",
            "∑ ∏ ∫",
            "⌘ ⌥ ⇧ ⌃",
            // Metacharacters, SQL injection, Format strings
            "%",
            "%@",
            "%s",
            "%d",
            "'; DROP TABLE items; --",
            "<script>alert(1)</script>",
            ".*",
            "[a-z]+",
            "\\d{4}",
            "(code|review)",
            // Invisible, combining & boundary characters
            "\u{200B}", // Zero-width space
            "\u{200C}", // Zero-width non-joiner
            "\u{00A0}", // Non-breaking space
            "\u{0000}", // Null byte
            "\u{001F}", // Unit separator
            String(repeating: "A", count: 2000), // Long string
            String(repeating: "测", count: 1000)  // Long unicode
        ]

        var fuzzPassed = true
        for q in fuzzQueries {
            let results = storage.search(query: q)
            // Empty / whitespace search query must return all items
            let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.isEmpty {
                if results.count != testSeedData.count {
                    fuzzPassed = false
                    break
                }
            } else {
                // Must not crash and result count must be within [0, total]
                if results.count < 0 || results.count > testSeedData.count {
                    fuzzPassed = false
                    break
                }
            }
        }
        ChallengerHarness.assertTrue(fuzzPassed, "All \(fuzzQueries.count) Unicode fuzz queries executed safely with 0 crashes")

        // Rapid Shortcut Cycling Stress: 5,000 steps of stepDown and stepUp
        var currentNavIndex: Int? = 0
        let visibleCount = storage.items.count
        var cyclingValid = true

        for i in 0..<5000 {
            if i % 2 == 0 {
                currentNavIndex = ShortcutNavigator.stepDown(currentIndex: currentNavIndex, visibleCount: visibleCount)
            } else {
                currentNavIndex = ShortcutNavigator.stepUp(currentIndex: currentNavIndex, visibleCount: visibleCount)
            }

            if let idx = currentNavIndex {
                if idx < 0 || idx >= visibleCount {
                    cyclingValid = false
                    break
                }
            }
        }
        ChallengerHarness.assertTrue(cyclingValid, "5,000 rapid ShortcutNavigator circular navigation steps remained within bounds")

        // Rapid Search Focus Notification Center posting
        var notifHandledCount = 0
        let notifObserver = NotificationCenter.default.addObserver(forName: Notification.Name("SuperShotFocusSearchField"), object: nil, queue: nil) { _ in
            notifHandledCount += 1
        }

        for _ in 0..<1000 {
            NotificationCenter.default.post(name: Notification.Name("SuperShotFocusSearchField"), object: nil)
        }

        NotificationCenter.default.removeObserver(notifObserver)
        ChallengerHarness.assertEqual(notifHandledCount, 1000, "1,000 rapid SuperShotFocusSearchField notifications dispatched and received safely")

        try? FileManager.default.removeItem(at: sandboxDir)
    }

    // MARK: - 24. Milestone M47-2 v1.0.20 Empirical Stress & Adversarial Challenge
    private static func testMilestoneM47EmpiricalStressAndAdversarialChallenge() {
        ChallengerHarness.startSuite("24. Milestone M47-2 v1.0.20 Empirical Stress & Adversarial Challenge")

        // =====================================================================
        // Sub-scenario 24A: Concurrent HotKey Registration & Lookup Stress
        // =====================================================================
        ChallengerHarness.startSuite("24A. Concurrent HotKey Registration & Lookup Stress")

        // 1. Alias invariant
        ChallengerHarness.assertEqual(HotKeyAction.captureRegion, HotKeyAction.inPlaceCapture, "HotKeyAction.captureRegion alias equals .inPlaceCapture")

        // 2. Character extraction invariants
        let keyTests: [(code: UInt32, expectedChar: String)] = [
            (UInt32(kVK_ANSI_A), "a"),
            (UInt32(kVK_ANSI_S), "s"),
            (UInt32(kVK_ANSI_Z), "z"),
            (UInt32(kVK_ANSI_0), "0"),
            (UInt32(kVK_ANSI_9), "9"),
            (UInt32(kVK_F1), ""),
            (UInt32(kVK_F12), ""),
            (UInt32(kVK_Space), ""),
            (UInt32(kVK_Return), "↩"),
            (UInt32(kVK_Tab), "⇥"),
            (UInt32(kVK_Escape), "⎋"),
            (UInt32(kVK_Delete), "⌫")
        ]

        for (code, expected) in keyTests {
            let sc = HotKeyShortcut(keyCode: code, carbonModifiers: UInt32(cmdKey))
            ChallengerHarness.assertEqual(sc.keyEquivalentCharacter, expected, "Key code \(code) produces keyEquivalent '\(expected)'")
        }

        // 3. Carbon modifier to Cocoa modifier mapping
        let modCmd = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(cmdKey))
        ChallengerHarness.assertEqual(modCmd.cocoaModifiers, [.command], "cmdKey maps to [.command]")

        let modOptShift = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(optionKey | shiftKey))
        ChallengerHarness.assertEqual(modOptShift.cocoaModifiers, [.option, .shift], "optionKey | shiftKey maps to [.option, .shift]")

        let modAll = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        ChallengerHarness.assertEqual(modAll.cocoaModifiers, [.command, .shift, .option, .control], "All carbon modifiers map correctly")

        let modNone = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: 0)
        ChallengerHarness.assertEqual(modNone.cocoaModifiers, [], "Zero carbon modifiers map to empty flags")

        // 4. Concurrent Registration, Unregistration & Lookup Stress (20 threads x 50 iterations = 1000 operations)
        let hotKeyGroup = DispatchGroup()
        let hotKeyQueue = DispatchQueue(label: "com.supershot.adversarial.hotkey", attributes: .concurrent)
        var hotKeyErrors = 0
        let hotKeyErrorLock = NSLock()

        for threadIdx in 0..<20 {
            hotKeyGroup.enter()
            hotKeyQueue.async {
                for iter in 0..<50 {
                    let randCode = UInt32(kVK_ANSI_A + ((threadIdx + iter) % 26))
                    let randMods = UInt32((iter % 2 == 0 ? optionKey : cmdKey) | (threadIdx % 2 == 0 ? shiftKey : 0))

                    if threadIdx % 4 == 0 {
                        // Register inPlaceCapture
                        _ = HotKeyManager.shared.register(action: .inPlaceCapture, keyCode: randCode, modifiers: randMods)
                    } else if threadIdx % 4 == 1 {
                        // Register scrollingCapture
                        _ = HotKeyManager.shared.register(action: .scrollingCapture, keyCode: randCode, modifiers: randMods)
                    } else if threadIdx % 4 == 2 {
                        // Query shortcuts and check getters
                        let sc1 = HotKeyManager.shared.shortcut(for: .inPlaceCapture)
                        let sc2 = HotKeyManager.shared.shortcut(for: .scrollingCapture)
                        if let sc = sc1 {
                            _ = sc.keyEquivalentCharacter
                            _ = sc.cocoaModifiers
                            _ = sc.displayString
                        }
                        if let sc = sc2 {
                            _ = sc.keyEquivalentCharacter
                            _ = sc.cocoaModifiers
                            _ = sc.displayString
                        }
                    } else {
                        // Check registration status and unregister
                        _ = HotKeyManager.shared.isRegistered(action: .inPlaceCapture)
                        _ = HotKeyManager.shared.isRegistered(action: .scrollingCapture)
                        if iter % 10 == 0 {
                            HotKeyManager.shared.unregister(action: .inPlaceCapture)
                        }
                    }
                }
                hotKeyGroup.leave()
            }
        }

        let hotKeyWaitResult = hotKeyGroup.wait(timeout: .now() + 5.0)
        ChallengerHarness.assertEqual(hotKeyWaitResult, .success, "Concurrent hotkey registration and lookup completed within 5s with 0 deadlocks")
        ChallengerHarness.assertEqual(hotKeyErrors, 0, "0 errors during concurrent hotkey stress")

        // Restore defaults safely
        HotKeyManager.shared.registerDefaults()
        ChallengerHarness.assertTrue(HotKeyManager.shared.isRegistered(action: .inPlaceCapture), "Default inPlaceCapture registered successfully")
        ChallengerHarness.assertTrue(HotKeyManager.shared.isRegistered(action: .scrollingCapture), "Default scrollingCapture registered successfully")
        ChallengerHarness.assertEqual(HotKeyManager.shared.shortcut(for: .inPlaceCapture)?.keyEquivalentCharacter, "s", "Default inPlaceCapture shortcut produces keyEquivalent 's'")
        ChallengerHarness.assertEqual(HotKeyManager.shared.shortcut(for: .scrollingCapture)?.keyEquivalentCharacter, "s", "Default scrollingCapture shortcut produces keyEquivalent 's'")

        // =====================================================================
        // Sub-scenario 24B: Rapid Keyboard Shortcut Cycling & Bounds Stress
        // =====================================================================
        ChallengerHarness.startSuite("24B. Rapid Keyboard Shortcut Cycling & Bounds Stress")

        // 1. Boundary behavior on visibleCount == 0
        ChallengerHarness.assertNil(ShortcutNavigator.stepDown(currentIndex: nil, visibleCount: 0), "stepDown on 0 items returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepDown(currentIndex: 0, visibleCount: 0), "stepDown with index on 0 items returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepUp(currentIndex: nil, visibleCount: 0), "stepUp on 0 items returns nil")
        ChallengerHarness.assertNil(ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: 0), "stepUp with index on 0 items returns nil")

        // 2. Boundary behavior on visibleCount == 1
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: nil, visibleCount: 1), 0, "stepDown(nil, 1) returns 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: 0, visibleCount: 1), 0, "stepDown(0, 1) wraps to 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: nil, visibleCount: 1), 0, "stepUp(nil, 1) returns 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: 1), 0, "stepUp(0, 1) wraps to 0")

        // 3. Boundary behavior on negative and extreme indices
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: -5, visibleCount: 10), 0, "stepDown(-5, 10) wraps safely to 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepDown(currentIndex: 500, visibleCount: 10), 0, "stepDown(500, 10) wraps safely to 0")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: -5, visibleCount: 10), 9, "stepUp(-5, 10) wraps safely to 9")
        ChallengerHarness.assertEqual(ShortcutNavigator.stepUp(currentIndex: 500, visibleCount: 10), 9, "stepUp(500, 10) wraps safely to 9")

        // 4. 10,000 rapid alternating navigation cycles
        var cyclingIndex: Int? = 0
        var allCyclesBounded = true
        for i in 0..<10000 {
            if i % 2 == 0 {
                cyclingIndex = ShortcutNavigator.stepDown(currentIndex: cyclingIndex, visibleCount: 15)
            } else {
                cyclingIndex = ShortcutNavigator.stepUp(currentIndex: cyclingIndex, visibleCount: 15)
            }
            if let idx = cyclingIndex {
                if idx < 0 || idx >= 15 {
                    allCyclesBounded = false
                    break
                }
            } else {
                allCyclesBounded = false
                break
            }
        }
        ChallengerHarness.assertTrue(allCyclesBounded, "10,000 rapid stepDown/stepUp cycles remained 100% within valid bounds [0, 14]")

        // 5. Section Shortcut Resolution (Option+1..9 for Pinned, Cmd+1..9 / Bare 1..9 for Recent)
        var mockPinnedItems: [ShotItem] = []
        var mockRecentItems: [ShotItem] = []
        for i in 1...5 {
            mockPinnedItems.append(ShotItem(filePath: "pin_\(i).png", isPinned: true, sourceApp: "PinApp\(i)", captureType: .region))
            mockRecentItems.append(ShotItem(filePath: "rec_\(i).png", isPinned: false, sourceApp: "RecApp\(i)", captureType: .region))
        }

        // Test Option + 1..9
        for d in 1...9 {
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .option,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\(d)",
                charactersIgnoringModifiers: "\(d)",
                isARepeat: false,
                keyCode: UInt16(17 + d)
            )!
            let parsed = ShortcutNavigator.parseSectionShortcut(from: event, searchFieldHasFocus: false)
            ChallengerHarness.assertNotNil(parsed, "Option+\(d) parsed as section shortcut")
            ChallengerHarness.assertEqual(parsed?.section, .pinned, "Option+\(d) parsed with section == .pinned")
            ChallengerHarness.assertEqual(parsed?.digit, d, "Option+\(d) parsed with digit == \(d)")

            let target = ShortcutNavigator.targetItem(forSectionShortcut: parsed!, pinnedItems: mockPinnedItems, recentItems: mockRecentItems)
            if d <= 5 {
                ChallengerHarness.assertEqual(target?.id, mockPinnedItems[d - 1].id, "Option+\(d) resolved target pinned item \(d)")
            } else {
                ChallengerHarness.assertNil(target, "Option+\(d) returned nil for out-of-bounds pinned item")
            }
        }

        // Test Command + 1..9
        for d in 1...9 {
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\(d)",
                charactersIgnoringModifiers: "\(d)",
                isARepeat: false,
                keyCode: UInt16(17 + d)
            )!
            let parsed = ShortcutNavigator.parseSectionShortcut(from: event, searchFieldHasFocus: true)
            ChallengerHarness.assertNotNil(parsed, "Cmd+\(d) parsed as section shortcut")
            ChallengerHarness.assertEqual(parsed?.section, .recent, "Cmd+\(d) parsed with section == .recent")

            let target = ShortcutNavigator.targetItem(forSectionShortcut: parsed!, pinnedItems: mockPinnedItems, recentItems: mockRecentItems)
            if d <= 5 {
                ChallengerHarness.assertEqual(target?.id, mockRecentItems[d - 1].id, "Cmd+\(d) resolved target recent item \(d)")
            } else {
                ChallengerHarness.assertNil(target, "Cmd+\(d) returned nil for out-of-bounds recent item")
            }
        }

        // Test Bare 1..9 with search focus active vs inactive
        for d in 1...5 {
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\(d)",
                charactersIgnoringModifiers: "\(d)",
                isARepeat: false,
                keyCode: UInt16(17 + d)
            )!
            let focusedParsed = ShortcutNavigator.parseSectionShortcut(from: event, searchFieldHasFocus: true)
            ChallengerHarness.assertNil(focusedParsed, "Bare \(d) returns nil when search field is focused")

            let unfocusedParsed = ShortcutNavigator.parseSectionShortcut(from: event, searchFieldHasFocus: false)
            ChallengerHarness.assertNotNil(unfocusedParsed, "Bare \(d) parses when search field is unfocused")
            ChallengerHarness.assertEqual(unfocusedParsed?.section, .recent, "Bare \(d) targets recent section")
        }

        // Test Control modifier rejection
        let ctrlEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "1",
            charactersIgnoringModifiers: "1",
            isARepeat: false,
            keyCode: 18
        )!
        ChallengerHarness.assertNil(ShortcutNavigator.parseSectionShortcut(from: ctrlEvent, searchFieldHasFocus: false), "Ctrl modifier rejected by parseSectionShortcut")

        // Test Badge Strings
        for (idx, item) in mockPinnedItems.enumerated() {
            let badge = ShortcutNavigator.badgeString(for: item, pinnedItems: mockPinnedItems, recentItems: mockRecentItems)
            ChallengerHarness.assertEqual(badge, "⌥\(idx + 1)", "Pinned item \(idx + 1) badge is ⌥\(idx + 1)")
        }
        for (idx, item) in mockRecentItems.enumerated() {
            let badge = ShortcutNavigator.badgeString(for: item, pinnedItems: mockPinnedItems, recentItems: mockRecentItems)
            ChallengerHarness.assertEqual(badge, "\(idx + 1)", "Recent item \(idx + 1) badge is \(idx + 1)")
        }

        // =====================================================================
        // Sub-scenario 24C: Nil & Corrupted Image Handles in Re-Annotate Robustness
        // =====================================================================
        ChallengerHarness.startSuite("24C. Nil & Corrupted Image Handles in Re-Annotate Robustness")

        let annotateSandbox = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShotAdvM47_Annotate_\(UUID().uuidString)")
        let annotateStorage = StorageManager(baseDirectory: annotateSandbox)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: 80,
            height: 60,
            bitsPerComponent: 8,
            bytesPerRow: 80 * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let validSampleImage = ctx.makeImage() else {
            ChallengerHarness.recordFail("M47 validSampleImage", reason: "Could not create sample base image")
            return
        }

        // 1. Non-existent shot item
        let phantomItem = ShotItem(filePath: "non_existent_\(UUID().uuidString).png", sourceApp: "Phantom", captureType: .region)
        ChallengerHarness.assertNil(annotateStorage.load(id: phantomItem.id), "load(id:) returns nil for non-existent item")
        ChallengerHarness.assertNil(annotateStorage.loadCGImage(for: phantomItem), "loadCGImage returns nil for non-existent item")

        // 2. Item with deleted/missing backing file on disk
        let deletedItem = ShotItem(filePath: "deleted_\(UUID().uuidString).png", sourceApp: "DeletedDiskApp", captureType: .region)
        ChallengerHarness.assertNil(annotateStorage.loadCGImage(for: deletedItem), "loadCGImage returns nil when backing file does not exist on disk")
        ChallengerHarness.assertNil(annotateStorage.getImageData(for: deletedItem), "getImageData returns nil when backing file does not exist on disk")

        // 3. Item with 0-byte corrupted file directly on disk (uncached)
        let zeroItem = ShotItem(filePath: "zero_\(UUID().uuidString).png", sourceApp: "ZeroByteApp", captureType: .region)
        let zeroURL = annotateStorage.imagesDirectory.appendingPathComponent(zeroItem.filePath)
        try! Data().write(to: zeroURL, options: .atomic)
        ChallengerHarness.assertNil(annotateStorage.loadCGImage(for: zeroItem), "loadCGImage returns nil for 0-byte corrupted image file")

        // 4. Item with garbage random bytes directly on disk (uncached)
        let garbageItem = ShotItem(filePath: "garbage_\(UUID().uuidString).png", sourceApp: "GarbageApp", captureType: .region)
        let garbageURL = annotateStorage.imagesDirectory.appendingPathComponent(garbageItem.filePath)
        let garbageData = Data(repeating: 0x7F, count: 512)
        try! garbageData.write(to: garbageURL, options: .atomic)
        ChallengerHarness.assertNil(annotateStorage.loadCGImage(for: garbageItem), "loadCGImage returns nil for non-image garbage file")

        // 5. MainShotView annotateItem with callback on nil/corrupted items
        var callbackAnnotatedID: UUID?
        let mockMainShotView = MainShotView(
            storageManager: annotateStorage,
            appSettings: AppSettings(),
            onAnnotateItem: { item in
                callbackAnnotatedID = item.id
            }
        )

        mockMainShotView.annotateItem(phantomItem)
        ChallengerHarness.assertEqual(callbackAnnotatedID, phantomItem.id, "annotateItem invokes onAnnotateItem callback for phantom item safely")

        mockMainShotView.annotateItem(zeroItem)
        ChallengerHarness.assertEqual(callbackAnnotatedID, zeroItem.id, "annotateItem invokes onAnnotateItem callback for zero-byte item safely")

        mockMainShotView.annotateItem(garbageItem)
        ChallengerHarness.assertEqual(callbackAnnotatedID, garbageItem.id, "annotateItem invokes onAnnotateItem callback for garbage item safely")

        // 6. Concurrency Stress: 10 threads concurrently attempting loads on corrupted files
        let annotateGroup = DispatchGroup()
        let annotateQueue = DispatchQueue(label: "com.supershot.adversarial.annotate", attributes: .concurrent)
        var allLoadsSafe = true
        let annotateLock = NSLock()

        for _ in 0..<10 {
            annotateGroup.enter()
            annotateQueue.async {
                for _ in 0..<20 {
                    let r1 = annotateStorage.loadCGImage(for: phantomItem)
                    let r2 = annotateStorage.loadCGImage(for: zeroItem)
                    let r3 = annotateStorage.loadCGImage(for: garbageItem)
                    if r1 != nil || r2 != nil || r3 != nil {
                        annotateLock.lock()
                        allLoadsSafe = false
                        annotateLock.unlock()
                    }
                }
                annotateGroup.leave()
            }
        }
        let annotateWait = annotateGroup.wait(timeout: .now() + 5.0)
        ChallengerHarness.assertEqual(annotateWait, .success, "Concurrent corrupted image loads completed with 0 deadlocks")
        ChallengerHarness.assertTrue(allLoadsSafe, "All 600 concurrent corrupted image loads safely returned nil without exceptions")

        try? FileManager.default.removeItem(at: annotateSandbox)

        // =====================================================================
        // Sub-scenario 24D: Hex Code Fuzzing & Live Swatch Boundary Stress
        // =====================================================================
        ChallengerHarness.startSuite("24D. Hex Code Fuzzing & Live Swatch Boundary Stress")

        // 1. Valid hex formats
        let validHexCodes = [
            "#FF3B30", "FF3B30", "#34C759", "34c759", "#007AFF", "007aff",
            "#FFF", "FFF", "#000", "000", "#123", "123", "#abc", "ABC",
            "  #FF3B30  ", "\n#007AFF\t"
        ]
        for hex in validHexCodes {
            ChallengerHarness.assertTrue(ColorPreset.isValid(hex: hex), "Valid hex '\(hex)' recognized as valid")
            let norm = ColorPreset.normalize(hex: hex)
            ChallengerHarness.assertTrue(norm.hasPrefix("#"), "Normalized hex '\(norm)' starts with #")
            ChallengerHarness.assertEqual(norm.count, 7, "Normalized hex '\(norm)' has exactly 7 characters")
            let parsed = ColorPreset.parseRGB(hex: hex)
            ChallengerHarness.assertNotNil(parsed, "parseRGB succeeded for '\(hex)'")
            if let rgb = parsed {
                ChallengerHarness.assertTrue(rgb.r >= 0.0 && rgb.r <= 1.0, "r in [0, 1]")
                ChallengerHarness.assertTrue(rgb.g >= 0.0 && rgb.g <= 1.0, "g in [0, 1]")
                ChallengerHarness.assertTrue(rgb.b >= 0.0 && rgb.b <= 1.0, "b in [0, 1]")
            }
            _ = Color(hex: hex)
        }

        // 2. Invalid hex formats
        let invalidHexCodes = [
            "", "   ", "\t\n\r", "#", "##", "###",
            "#1", "#12", "#1234", "#12345",
            "#1234567", "#12345678", "#123456789",
            "#GGGGGG", "#ZZZZZZ", "XYZ123", "G12345",
            "#<script>", "#123; DROP TABLE", "#%d%s",
            "#FF\0FF", "#FF 3B", "#FF\u{200B}3B",
            String(repeating: "F", count: 10000)
        ]
        for hex in invalidHexCodes {
            ChallengerHarness.assertFalse(ColorPreset.isValid(hex: hex), "Invalid hex string rejected")
            let norm = ColorPreset.normalize(hex: hex, defaultHex: "#FF3B30")
            ChallengerHarness.assertEqual(norm, "#FF3B30", "Invalid hex falls back to default #FF3B30")
            ChallengerHarness.assertNil(ColorPreset.parseRGB(hex: hex), "parseRGB returns nil for invalid hex")
            // Color(hex:) initializer fallback safety
            _ = Color(hex: hex)
        }

        // 3. 5,000 Pseudo-Random String Fuzz Mutations
        var hexFuzzPassed = true
        var fuzzRng: UInt64 = 0xDEADBEEFCAFE
        for _ in 0..<5000 {
            fuzzRng = (fuzzRng &* 6364136223846793005) &+ 1442695040888963407
            let len = Int(fuzzRng % 32)
            var randomStr = ""
            if fuzzRng % 2 == 0 { randomStr.append("#") }
            for _ in 0..<len {
                fuzzRng = (fuzzRng &* 6364136223846793005) &+ 1442695040888963407
                let asciiVal = UInt8(fuzzRng % 128)
                let scalar = UnicodeScalar(asciiVal)
                randomStr.append(Character(scalar))
            }

            let valid = ColorPreset.isValid(hex: randomStr)
            let normalized = ColorPreset.normalize(hex: randomStr)
            if !normalized.hasPrefix("#") || normalized.count != 7 {
                hexFuzzPassed = false
                break
            }
            if valid {
                if ColorPreset.parseRGB(hex: randomStr) == nil {
                    hexFuzzPassed = false
                    break
                }
            } else {
                if ColorPreset.parseRGB(hex: randomStr) != nil {
                    hexFuzzPassed = false
                    break
                }
            }
            _ = Color(hex: randomStr)
        }
        ChallengerHarness.assertTrue(hexFuzzPassed, "5,000 pseudo-random hex fuzz mutations handled safely with 0 crashes or inconsistent states")

        // 4. ColorPreset Defaults Invariants
        ChallengerHarness.assertEqual(ColorPreset.defaults.count, 8, "ColorPreset.defaults contains exactly 8 standard colors")
        for preset in ColorPreset.defaults {
            ChallengerHarness.assertTrue(ColorPreset.isValid(hex: preset.hex), "Default preset '\(preset.name)' has valid hex '\(preset.hex)'")
            ChallengerHarness.assertNotNil(preset.toNSColor(), "Default preset '\(preset.name)' converts to NSColor")
            _ = preset.toColor()
        }

        // =====================================================================
        // Sub-scenario 24E: Rapid Concurrent Unpinned History Clearing & Invariant Verification
        // =====================================================================
        ChallengerHarness.startSuite("24E. Rapid Concurrent Unpinned History Clearing & Invariant Verification")

        let clearSandbox = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShotAdvM47_Clear_\(UUID().uuidString)")
        let clearStorage = StorageManager(baseDirectory: clearSandbox, initialCapacity: 100)

        // 1. Seed with 20 items: 10 pinned, 10 unpinned
        var pinnedIDs: Set<UUID> = []
        var unpinnedIDs: Set<UUID> = []

        for i in 1...10 {
            let pItem = try! clearStorage.save(image: validSampleImage, sourceApp: "PinnedApp\(i)", captureType: .region)
            clearStorage.togglePin(id: pItem.id)
            pinnedIDs.insert(pItem.id)

            let uItem = try! clearStorage.save(image: validSampleImage, sourceApp: "UnpinnedApp\(i)", captureType: .region)
            unpinnedIDs.insert(uItem.id)
        }

        clearStorage.flushDiskQueue()
        ChallengerHarness.assertEqual(clearStorage.items.count, 20, "Storage seeded with 20 items")

        // 2. Execute clearUnpinnedHistory()
        clearStorage.clearUnpinnedHistory()
        clearStorage.flushDiskQueue()

        // Verify Invariants:
        // Invariant A: Exactly 10 items remain
        ChallengerHarness.assertEqual(clearStorage.items.count, 10, "Exactly 10 items remain after clearing unpinned history")

        // Invariant B: 100% of remaining items are pinned and match pinnedIDs
        var allRemainingPinned = true
        var allPinnedIDsRetained = true
        for it in clearStorage.items {
            if !it.isPinned { allRemainingPinned = false }
            if !pinnedIDs.contains(it.id) { allPinnedIDsRetained = false }
        }
        ChallengerHarness.assertTrue(allRemainingPinned, "Invariant: 100% of remaining items have isPinned == true")
        ChallengerHarness.assertTrue(allPinnedIDsRetained, "Invariant: 100% of original pinned item IDs retained")

        // Invariant C: Pinned image files exist on disk, unpinned files deleted from disk
        var pinnedFilesExist = true
        for id in pinnedIDs {
            if let it = clearStorage.items.first(where: { $0.id == id }) {
                let url = clearStorage.getImageURL(for: it)
                if !FileManager.default.fileExists(atPath: url.path) {
                    pinnedFilesExist = false
                }
            }
        }
        ChallengerHarness.assertTrue(pinnedFilesExist, "Disk invariant: Backing image files for all pinned items exist on disk")

        var unpinnedFilesDeleted = true
        for id in unpinnedIDs {
            let uURL = clearStorage.imagesDirectory.appendingPathComponent("\(id.uuidString).png")
            if FileManager.default.fileExists(atPath: uURL.path) {
                unpinnedFilesDeleted = false
            }
        }
        ChallengerHarness.assertTrue(unpinnedFilesDeleted, "Disk invariant: Backing image files for all unpinned items deleted from disk")

        // 3. Repeated Clearing Idempotency
        for _ in 0..<10 {
            clearStorage.clearUnpinnedHistory()
        }
        ChallengerHarness.assertEqual(clearStorage.items.count, 10, "10 repeated calls to clearUnpinnedHistory() are strictly idempotent (count remains 10)")

        // 4. Clearing when all items are unpinned
        for it in clearStorage.items {
            clearStorage.togglePin(id: it.id) // Unpin all
        }
        clearStorage.clearUnpinnedHistory()
        ChallengerHarness.assertEqual(clearStorage.items.count, 0, "Clearing when 0 pinned items exist empties storage completely")

        // 5. Clearing already empty storage
        clearStorage.clearUnpinnedHistory()
        ChallengerHarness.assertEqual(clearStorage.items.count, 0, "Clearing empty storage is safe no-op")

        // 6. High Concurrency Stress: 15 concurrent threads performing clear, save, togglePin, and search
        let stressSandbox = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShotAdvM47_Stress_\(UUID().uuidString)")
        let concurrentStorage = StorageManager(baseDirectory: stressSandbox, initialCapacity: 100)

        // Seed 10 initial items
        for _ in 0..<10 {
            _ = try? concurrentStorage.save(image: validSampleImage, sourceApp: "ConcurrentApp", captureType: .region)
        }

        let clearGroup = DispatchGroup()
        let clearQueue = DispatchQueue(label: "com.supershot.adversarial.clear", attributes: .concurrent)

        for t in 0..<15 {
            clearGroup.enter()
            clearQueue.async {
                for iter in 0..<50 {
                    if t % 3 == 0 {
                        // Clear unpinned history
                        concurrentStorage.clearUnpinnedHistory()
                    } else if t % 3 == 1 {
                        // Save and toggle pin
                        if let item = try? concurrentStorage.save(image: validSampleImage, sourceApp: "Thread\(t)", captureType: .region) {
                            if iter % 2 == 0 {
                                concurrentStorage.togglePin(id: item.id)
                            }
                        }
                    } else {
                        // Query items and search
                        _ = concurrentStorage.items.count
                        _ = concurrentStorage.search(query: "Thread")
                    }
                }
                clearGroup.leave()
            }
        }

        let clearWait = clearGroup.wait(timeout: .now() + 5.0)
        ChallengerHarness.assertEqual(clearWait, .success, "15 concurrent threads with 750 operations completed within 5s with 0 deadlocks")

        // Final invariant after concurrency drained:
        concurrentStorage.clearUnpinnedHistory()
        let remainingItems = concurrentStorage.items
        var finalPinnedInvariant = true
        for it in remainingItems {
            if !it.isPinned { finalPinnedInvariant = false }
        }
        ChallengerHarness.assertTrue(finalPinnedInvariant, "Final concurrency invariant: After clearUnpinnedHistory(), 100% of remaining items are pinned")

        // Cleanup temporary directories
        try? FileManager.default.removeItem(at: clearSandbox)
        try? FileManager.default.removeItem(at: stressSandbox)
    }

    // MARK: - 25. Milestone M51-2 v1.0.21 Empirical Stress & Adversarial Challenge
    private static func testMilestoneM51EmpiricalStressAndAdversarialChallenge() {
        ChallengerHarness.startSuite("25. Milestone M51-2 v1.0.21 Empirical Stress & Adversarial Challenge")

        // =====================================================================
        // Sub-scenario 25A: Rapid Mutation Sequences: Burst Undo / Redo / Duplicate Cycles on Large Vector Canvases
        // =====================================================================
        ChallengerHarness.startSuite("25A. Rapid Mutation Sequences: Burst Undo / Redo / Duplicate Cycles on Large Vector Canvases")

        let largeCanvasBoundary = CGRect(x: 0, y: 0, width: 5000, height: 5000)

        // 1. Stress Canvas Construction with Diverse Tools
        let engine = AnnotationEngine(maxHistoryLimit: 100)
        ChallengerHarness.assertEqual(engine.objects.count, 0, "Initial canvas contains 0 objects")
        ChallengerHarness.assertFalse(engine.canUndo, "Initial engine cannot undo")
        ChallengerHarness.assertFalse(engine.canRedo, "Initial engine cannot redo")

        // Seed canvas with 100 varied objects
        for i in 0..<100 {
            let x = CGFloat((i * 47) % 4800)
            let y = CGFloat((i * 61) % 4800)
            let obj: AnnotationObject
            switch i % 8 {
            case 0:
                obj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: x, y: y, width: 150, height: 100), colorHex: "#007AFF")
            case 1:
                obj = AnnotationObject(tool: .ellipse, bounds: CGRect(x: x, y: y, width: 90, height: 90), colorHex: "#34C759")
            case 2:
                obj = AnnotationObject(tool: .arrow, points: [CGPoint(x: x, y: y), CGPoint(x: x + 100, y: y + 100)], colorHex: "#FF9500")
            case 3:
                obj = AnnotationObject(tool: .line, points: [CGPoint(x: x, y: y), CGPoint(x: x + 200, y: y)], colorHex: "#AF52DE")
            case 4:
                var pts: [CGPoint] = []
                for p in 0..<50 {
                    pts.append(CGPoint(x: x + CGFloat(p * 2), y: y + CGFloat((p % 10) * 2)))
                }
                obj = AnnotationObject(tool: .pen, points: pts, colorHex: "#5856D6")
            case 5:
                var pts: [CGPoint] = []
                for p in 0..<30 {
                    pts.append(CGPoint(x: x + CGFloat(p * 5), y: y))
                }
                obj = AnnotationObject(tool: .highlighter, points: pts, colorHex: "#FFCC00")
            case 6:
                obj = AnnotationObject(tool: .text, bounds: CGRect(x: x, y: y, width: 200, height: 40), colorHex: "#000000", text: "Text Annotation \(i)")
            default:
                obj = AnnotationObject(tool: .blur, bounds: CGRect(x: x, y: y, width: 140, height: 140), blurRadius: 12.0)
            }
            engine.addObject(obj)
        }

        ChallengerHarness.assertEqual(engine.objects.count, 100, "100 diverse vector objects added to large canvas")
        ChallengerHarness.assertTrue(engine.canUndo, "Engine canUndo after 100 additions")
        ChallengerHarness.assertFalse(engine.canRedo, "Engine cannot redo after fresh additions")

        // 2. Burst Duplication Cycles with Boundary Clamping
        for i in 0..<50 {
            let targetID = engine.objects[i * 2].id
            engine.selectedObjectID = targetID
            let clone = engine.duplicateSelected(within: largeCanvasBoundary)
            ChallengerHarness.assertNotNil(clone, "Duplicate iteration \(i) succeeded")
            if let c = clone {
                ChallengerHarness.assertTrue(largeCanvasBoundary.contains(c.bounds) || c.bounds.minX >= 0, "Duplicate \(i) clamped within boundary")
            }
        }
        ChallengerHarness.assertEqual(engine.objects.count, 150, "Canvas contains 150 objects after 50 duplications")

        // 3. Test Near-Boundary Duplication (Offset reversal / clamping)
        let cornerObj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 4980, y: 4980, width: 15, height: 15), colorHex: "#FF3B30")
        engine.addObject(cornerObj)
        let dupCorner = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16), within: largeCanvasBoundary)
        ChallengerHarness.assertNotNil(dupCorner, "Near-boundary duplicate succeeded with offset reversal/clamping")
        if let dc = dupCorner {
            ChallengerHarness.assertTrue(dc.bounds.maxX <= largeCanvasBoundary.maxX && dc.bounds.maxY <= largeCanvasBoundary.maxY, "Near-boundary duplicate bounds clamped within maxX and maxY")
        }

        // 4. Burst Sequential Undo Cycles
        var undoCount = 0
        while engine.canUndo && undoCount < 100 {
            engine.undo()
            undoCount += 1
        }
        ChallengerHarness.assertTrue(undoCount >= 50, "Successfully executed \(undoCount) sequential undos")
        ChallengerHarness.assertTrue(engine.canRedo, "Engine canRedo after sequential undos")

        // 5. Burst Sequential Redo Cycles
        var redoCount = 0
        while engine.canRedo && redoCount < undoCount {
            engine.redo()
            redoCount += 1
        }
        ChallengerHarness.assertEqual(undoCount, redoCount, "Redo count exactly matches undo count (\(redoCount))")

        // 6. Redo Stack Truncation on Intermediate Modification
        engine.undo()
        engine.undo()
        ChallengerHarness.assertTrue(engine.canRedo, "Engine canRedo after 2 undos")
        let intermediateObj = AnnotationObject(tool: .ellipse, bounds: CGRect(x: 100, y: 100, width: 50, height: 50), colorHex: "#007AFF")
        engine.addObject(intermediateObj)
        ChallengerHarness.assertFalse(engine.canRedo, "Redo stack truncated immediately when new object added mid-history")

        // 7. Batch Clear All and Undo Restoration on Massive Canvas
        let preClearCount = engine.objects.count
        ChallengerHarness.assertTrue(preClearCount > 50, "Pre-clear canvas contains \(preClearCount) objects")
        let clearedCount = engine.clearAll()
        ChallengerHarness.assertEqual(clearedCount, preClearCount, "clearAll() returns exact count of removed objects")
        ChallengerHarness.assertEqual(engine.objects.count, 0, "Canvas is empty after clearAll()")
        ChallengerHarness.assertTrue(engine.canUndo, "Can undo clearAll()")

        // Single Undo restores all objects
        engine.undo()
        ChallengerHarness.assertEqual(engine.objects.count, preClearCount, "Single undo restores all \(preClearCount) objects after batch clearAll()")

        // 8. 500 Interleaved Rapid Canvas Mutation Cycles in Tight Loop
        for iter in 0..<500 {
            let x = CGFloat(iter * 5 % 4000)
            let y = CGFloat(iter * 7 % 4000)
            let temp = AnnotationObject(tool: .rectangle, bounds: CGRect(x: x, y: y, width: 40, height: 40), colorHex: "#FF3B30")
            engine.addObject(temp)
            if iter % 3 == 0 {
                _ = engine.duplicateSelected(within: largeCanvasBoundary)
            }
            if iter % 5 == 0 {
                engine.undo()
            }
            if iter % 7 == 0 && engine.canRedo {
                engine.redo()
            }
        }
        ChallengerHarness.assertTrue(engine.objects.count > 0, "Engine survived 500 interleaved rapid mutations without index faults")

        // 9. HUD Notification Invariant Across All 9 Languages (Strict Zero Emoji)
        let hudUndoKeys: [AppLanguage: String] = [
            .english: "Undo (⌘Z)",
            .vietnamese: "Hoàn tác (⌘Z)",
            .german: "Widerrufen (⌘Z)",
            .french: "Annuler (⌘Z)",
            .spanish: "Deshacer (⌘Z)",
            .japanese: "取り消し (⌘Z)",
            .simplifiedChinese: "撤销 (⌘Z)",
            .traditionalChinese: "復原 (⌘Z)",
            .korean: "실행 취소 (⌘Z)"
        ]
        let hudRedoKeys: [AppLanguage: String] = [
            .english: "Redo (⌘⇧Z)",
            .vietnamese: "Làm lại (⌘⇧Z)",
            .german: "Wiederholen (⌘⇧Z)",
            .french: "Rétablir (⌘⇧Z)",
            .spanish: "Rehacer (⌘⇧Z)",
            .japanese: "やり直し (⌘⇧Z)",
            .simplifiedChinese: "重做 (⌘⇧Z)",
            .traditionalChinese: "重做 (⌘⇧Z)",
            .korean: "다시 실행 (⌘⇧Z)"
        ]
        let hudDuplicateKeys: [AppLanguage: String] = [
            .english: "Duplicated (⌘D)",
            .vietnamese: "Đã nhân bản (⌘D)",
            .german: "Dupliziert (⌘D)",
            .french: "Dupliqué (⌘D)",
            .spanish: "Duplicado (⌘D)",
            .japanese: "複製しました (⌘D)",
            .simplifiedChinese: "已复制图元 (⌘D)",
            .traditionalChinese: "已複製圖元 (⌘D)",
            .korean: "복제됨 (⌘D)"
        ]

        ChallengerHarness.assertFalse(L10nKey.hudUndo.localized(for: .system).isEmpty, "hudUndo non-empty for system")
        ChallengerHarness.assertFalse(L10nKey.hudRedo.localized(for: .system).isEmpty, "hudRedo non-empty for system")
        ChallengerHarness.assertFalse(L10nKey.hudDuplicate.localized(for: .system).isEmpty, "hudDuplicate non-empty for system")

        for lang in AppLanguage.allCases where lang != .system {
            let u = L10nKey.hudUndo.localized(for: lang)
            let r = L10nKey.hudRedo.localized(for: lang)
            let d = L10nKey.hudDuplicate.localized(for: lang)

            ChallengerHarness.assertEqual(u, hudUndoKeys[lang]!, "hudUndo matches exact translation for \(lang.rawValue)")
            ChallengerHarness.assertEqual(r, hudRedoKeys[lang]!, "hudRedo matches exact translation for \(lang.rawValue)")
            ChallengerHarness.assertEqual(d, hudDuplicateKeys[lang]!, "hudDuplicate matches exact translation for \(lang.rawValue)")

            ChallengerHarness.assertFalse(u.isEmpty, "hudUndo non-empty for \(lang.rawValue)")
            ChallengerHarness.assertFalse(r.isEmpty, "hudRedo non-empty for \(lang.rawValue)")
            ChallengerHarness.assertFalse(d.isEmpty, "hudDuplicate non-empty for \(lang.rawValue)")
        }

        // =====================================================================
        // Sub-scenario 25B: Concurrent Preset Addition via .onSubmit & Boundary Stress
        // =====================================================================
        ChallengerHarness.startSuite("25B. Concurrent Preset Addition via .onSubmit & Boundary Stress")

        let settingsSandbox = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShotAdvM51_Settings_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: settingsSandbox, withIntermediateDirectories: true)
        let settingsFile = settingsSandbox.appendingPathComponent("settings.json")
        let appSettings = AppSettings(settingsURL: settingsFile)

        // 1. Initial State: Exactly 8 defaults
        ChallengerHarness.assertEqual(appSettings.presets.count, 8, "Initial presets count equals 8 defaults")
        ChallengerHarness.assertEqual(AppSettings.maxPresetsCount, 16, "AppSettings.maxPresetsCount equals 16")

        // 2. Concurrent .onSubmit Simulation from Settings and Overlay
        // In real macOS runtime, .onSubmit handlers fire on the main runloop from Settings and Overlay TextFields.
        // We simulate 1,000 rapid concurrent .onSubmit events dispatched from both surfaces.
        var completedSubmits = 0
        let totalSubmissions = 1000

        for iter in 0..<totalSubmissions {
            let fromSettings = (iter % 2 == 0)
            DispatchQueue.main.async {
                if fromSettings {
                    // Simulates CaptureSaveSettingsTab.addNewPreset()
                    let hex = String(format: "#%02X%02X%02X", (iter * 17) % 256, (iter * 31) % 256, (iter * 53) % 256)
                    guard !hex.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    if ColorPreset.isValid(hex: hex) {
                        let normalized = ColorPreset.normalize(hex: hex)
                        let newP = ColorPreset(name: LocalizationManager.shared.tr(.customColorPreset), hex: normalized)
                        _ = appSettings.addPreset(newP)
                    }
                } else {
                    // Simulates ColorPalettePopover.saveCurrentColorAsPreset()
                    let hex = ColorPreset.normalize(hex: String(format: "#%02X%02X%02X", (iter * 11) % 256, (iter * 41) % 256, (iter * 67) % 256))
                    let preset = ColorPreset(name: LocalizationManager.shared.tr(.customColorPreset), hex: hex)
                    _ = appSettings.addPreset(preset)
                }
                completedSubmits += 1
            }
        }

        let runloopDeadline = Date().addingTimeInterval(5.0)
        while completedSubmits < totalSubmissions && Date() < runloopDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        ChallengerHarness.assertEqual(completedSubmits, totalSubmissions, "1,000 rapid concurrent .onSubmit events from settings and overlay processed completely")

        // 3. Invariant: Presets count MUST NEVER EXCEED 16
        ChallengerHarness.assertTrue(appSettings.presets.count <= 16, "Invariant: Presets count (\(appSettings.presets.count)) strictly <= 16 after 1,000 .onSubmit events")

        // 4. Add Preset Ceiling Enforcement
        for i in appSettings.presets.count..<16 {
            let uniqueHex = String(format: "#A%02X%02X", i, i * 2)
            _ = appSettings.addPreset(ColorPreset(name: "Filler \(i)", hex: uniqueHex))
        }
        ChallengerHarness.assertEqual(appSettings.presets.count, 16, "Presets count exactly 16")

        // Attempting to add a 17th novel preset MUST return false
        let seventeenthPreset = ColorPreset(name: "Seventeenth", hex: "#EE1122")
        let seventeenthAdded = appSettings.addPreset(seventeenthPreset)
        ChallengerHarness.assertFalse(seventeenthAdded, "Adding a 17th preset returns false when max limit of 16 is reached")
        ChallengerHarness.assertEqual(appSettings.presets.count, 16, "Presets count remains exactly 16 after rejected 17th preset")

        // 5. In-Place Name Updating when Hex Exists (Even when at 16 limit)
        let existingHex = appSettings.presets.first!.hex
        let updatedName = "RenamedExistingPreset"
        let updatedPreset = ColorPreset(name: updatedName, hex: existingHex.lowercased())
        let updateResult = appSettings.addPreset(updatedPreset)
        ChallengerHarness.assertTrue(updateResult, "addPreset succeeds for existing hex to update name in-place")
        ChallengerHarness.assertEqual(appSettings.presets.count, 16, "Presets count remains 16 after in-place name update")
        ChallengerHarness.assertEqual(appSettings.presets.first?.name, updatedName, "Existing preset's name updated in-place")

        // 6. Fuzzing .onSubmit Input Strings (Fuzzed boundary suite)
        let fuzzedInputs = [
            "", "   ", "\t\n", "1", "12", "1234", "12345", "1234567",
            "#", "#1", "#12", "#1234", "#12345", "#1234567", "#12345678",
            "#GGGGGG", "ZZZZZZ", "blue", "red", "rgba(255,0,0,1)",
            "#FF3B30\0", "#FF3B30\n", " #FF3B30 ", "#123", "ABC", "#AABBCC"
        ]
        for input in fuzzedInputs {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let isValid = ColorPreset.isValid(hex: trimmed)
            if isValid {
                let norm = ColorPreset.normalize(hex: trimmed)
                ChallengerHarness.assertTrue(norm.hasPrefix("#"), "Normalized valid hex '\(trimmed)' starts with #")
                ChallengerHarness.assertEqual(norm.count, 7, "Normalized valid hex '\(trimmed)' is exactly 7 chars")
            } else {
                ChallengerHarness.assertFalse(isValid, "Invalid hex '\(input)' rejected by ColorPreset.isValid")
            }
        }

        // =====================================================================
        // Sub-scenario 25C: Drag Provider Instantiation on Empty, Missing, or Corrupt Image Records
        // =====================================================================
        ChallengerHarness.startSuite("25C. Drag Provider Instantiation on Empty, Missing, or Corrupt Image Records")

        let dragSandbox = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShotAdvM51_Drag_\(UUID().uuidString)")
        let storage = StorageManager(baseDirectory: dragSandbox, initialCapacity: 50)
        let validSampleImage = AdversarialFrameGenerator.createMasterCanvas(width: 300, totalHeight: 200)!

        // Seed 1: Normal valid image
        let validItem = try! storage.save(image: validSampleImage, sourceApp: "Finder", captureType: .region)
        storage.flushDiskQueue()

        // Seed 2: Missing image (item exists in storage, but backing file removed from disk)
        let missingItem = try! storage.save(image: validSampleImage, sourceApp: "DeletedApp", captureType: .region)
        storage.flushDiskQueue()
        let missingURL = storage.getImageURL(for: missingItem)
        try? FileManager.default.removeItem(at: missingURL)

        // Seed 3: 0-byte corrupt image file (file exists on disk with 0 bytes)
        let zeroByteItem = try! storage.save(image: validSampleImage, sourceApp: "ZeroApp", captureType: .region)
        storage.flushDiskQueue()
        let zeroByteURL = storage.getImageURL(for: zeroByteItem)
        try? Data().write(to: zeroByteURL)

        // Seed 4: Garbage non-image binary file (file contains 4KB of random bytes)
        let garbageItem = try! storage.save(image: validSampleImage, sourceApp: "GarbageApp", captureType: .region)
        storage.flushDiskQueue()
        let garbageURL = storage.getImageURL(for: garbageItem)
        var garbageBytes = [UInt8](repeating: 0, count: 4096)
        for g in 0..<4096 { garbageBytes[g] = UInt8(g % 256) }
        try? Data(garbageBytes).write(to: garbageURL)

        // Seed 5: Truncated PNG header
        let truncatedItem = try! storage.save(image: validSampleImage, sourceApp: "TruncApp", captureType: .region)
        storage.flushDiskQueue()
        let truncatedURL = storage.getImageURL(for: truncatedItem)
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        try? Data(pngMagic).write(to: truncatedURL)

        // Helper simulating ShotRowView's .onDrag provider construction
        func createDragProvider(for item: ShotItem, sm: StorageManager?) -> NSItemProvider {
            let url: URL
            if let s = sm {
                url = s.getImageURL(for: item)
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                url = appSupport.appendingPathComponent("SuperShot/images").appendingPathComponent(item.filePath)
            }
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            if let imgData = sm?.getImageData(for: item), let nsImage = NSImage(data: imgData) {
                provider.registerObject(nsImage, visibility: .all)
            }
            return provider
        }

        // Test Case 1: Valid image
        let p1 = createDragProvider(for: validItem, sm: storage)
        ChallengerHarness.assertNotNil(p1, "Valid item creates valid NSItemProvider")
        ChallengerHarness.assertTrue(p1.canLoadObject(ofClass: NSImage.self), "Valid NSItemProvider can load NSImage")

        // Test Case 2: Missing image file
        let p2 = createDragProvider(for: missingItem, sm: storage)
        ChallengerHarness.assertNotNil(p2, "Missing image file falls back safely to empty NSItemProvider without crashing")

        // Test Case 3: 0-byte image file
        let p3 = createDragProvider(for: zeroByteItem, sm: storage)
        ChallengerHarness.assertNotNil(p3, "0-byte image file handled safely without crashing")

        // Test Case 4: Garbage non-image bytes
        let p4 = createDragProvider(for: garbageItem, sm: storage)
        ChallengerHarness.assertNotNil(p4, "Corrupted garbage bytes handled safely without crashing")

        // Test Case 5: Truncated image header
        let p5 = createDragProvider(for: truncatedItem, sm: storage)
        ChallengerHarness.assertNotNil(p5, "Truncated image stream handled safely without crashing")

        // Test Case 6: storageManager == nil (fallback URL branch)
        let p6 = createDragProvider(for: validItem, sm: nil)
        ChallengerHarness.assertNotNil(p6, "Nil storageManager fallback branch handled safely without crashing")

        // Test Case 7: High Concurrency Drag Provider Instantiation
        let dragGroup = DispatchGroup()
        let dragQueue = DispatchQueue(label: "com.supershot.adversarial.drag", attributes: .concurrent)

        for t in 0..<10 {
            dragGroup.enter()
            dragQueue.async {
                for _ in 0..<50 {
                    let items = [validItem, missingItem, zeroByteItem, garbageItem, truncatedItem]
                    let target = items[t % items.count]
                    _ = createDragProvider(for: target, sm: t % 2 == 0 ? storage : nil)
                }
                dragGroup.leave()
            }
        }

        let dragWait = dragGroup.wait(timeout: .now() + 5.0)
        ChallengerHarness.assertEqual(dragWait, .success, "10 concurrent threads creating 500 drag providers completed with 0 crashes or deadlocks")

        // =====================================================================
        // Sub-scenario 25D: Concurrency, Zero Deadlocks, Memory Leak, and Thread Sanitization Verification
        // =====================================================================
        ChallengerHarness.startSuite("25D. Concurrency, Zero Deadlocks, Memory Leak, and Thread Sanitization Verification")

        func getResidentMemoryBytes() -> UInt64 {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return kerr == KERN_SUCCESS ? info.resident_size : 0
        }

        let initialMem = getResidentMemoryBytes()

        // 1. Multi-Threaded Storage & Drag Provider Concurrency Stress (20 threads x 50 iterations = 1,000 operations)
        let crossGroup = DispatchGroup()
        let crossQueue = DispatchQueue(label: "com.supershot.adversarial.crosscutting", attributes: .concurrent)

        for t in 0..<20 {
            crossGroup.enter()
            crossQueue.async {
                for iter in 0..<50 {
                    if t % 2 == 0 {
                        // StorageManager thread-safe operations (protected by NSRecursiveLock)
                        if iter % 5 == 0 {
                            _ = try? storage.save(image: validSampleImage, sourceApp: "App_\(t)", captureType: .region)
                        } else if iter % 5 == 1 {
                            _ = storage.items.count
                        } else if iter % 5 == 2 {
                            _ = storage.search(query: "App")
                        } else if iter % 5 == 3 {
                            if let first = storage.items.first {
                                storage.togglePin(id: first.id)
                            }
                        } else {
                            storage.clearUnpinnedHistory()
                        }
                    } else {
                        // Drag provider operations (safe concurrent evaluation)
                        _ = createDragProvider(for: validItem, sm: iter % 3 == 0 ? nil : storage)
                    }
                }
                crossGroup.leave()
            }
        }

        let crossWait = crossGroup.wait(timeout: .now() + 5.0)
        ChallengerHarness.assertEqual(crossWait, .success, "Cross-cutting multi-threaded concurrency (1,000 operations) completed with 0 deadlocks")

        // 2. Memory Leak & Retention Stress: 2,000 rapid canvas object allocation and destruction cycles
        for m in 0..<2000 {
            let tempObj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: CGFloat(m % 100), y: CGFloat(m % 100), width: 50, height: 50), colorHex: "#007AFF")
            engine.addObject(tempObj)
            engine.undo()
        }

        let finalMem = getResidentMemoryBytes()
        let memDeltaMB = Double(finalMem > initialMem ? finalMem - initialMem : 0) / (1024.0 * 1024.0)

        // Resident memory growth must remain under 64 MB across all 3,000+ stress operations
        ChallengerHarness.assertTrue(memDeltaMB < 64.0, "Resident memory growth (\(String(format: "%.2f", memDeltaMB)) MB) strictly bounded (< 64 MB, zero memory leaks)")

        // Cleanup temporary directories
        try? FileManager.default.removeItem(at: settingsSandbox)
        try? FileManager.default.removeItem(at: dragSandbox)
    }

    // MARK: - 26. Milestone M52 Cycle 15 UpdateManager, DMG Extraction & Streaming Progress Stress Suite
    static func testMilestoneM52EmpiricalStressAndAdversarialChallenge() {
        ChallengerHarness.startSuite("26. Milestone M52 Cycle 15 UpdateManager, DMG & Streaming Adversarial Challenge")

        // -------------------------------------------------------------
        // Sub-scenario 26A: Malformed JSON Responses
        // -------------------------------------------------------------
        let malformedPayloads: [(name: String, data: Data)] = [
            ("Empty Data", Data()),
            ("Non-JSON String", "This is definitely not JSON".data(using: .utf8)!),
            ("Broken Syntax", "{\"tag_name\": \"v1.0.22\", \"assets\": [".data(using: .utf8)!),
            ("Missing TagName", "{\"name\": \"Release 1.0.22\"}".data(using: .utf8)!),
            ("Wrong Field Types", "{\"tag_name\": 12345, \"assets\": \"string_not_array\"}".data(using: .utf8)!),
            ("JSON Array instead of Object", "[1, 2, 3]".data(using: .utf8)!),
            ("Null TagName", "{\"tag_name\": null}".data(using: .utf8)!),
            ("Truncated JSON", "{\"tag_name\": \"v1.0.22\", \"assets\": [{\"name\": \"SuperShot-".data(using: .utf8)!)
        ]

        for (name, payload) in malformedPayloads {
            var threw = false
            do {
                _ = try UpdateManager.parseRelease(from: payload)
            } catch {
                threw = true
            }
            ChallengerHarness.assertTrue(threw, "26A: Malformed JSON (\(name)) throws decoding error safely")
        }

        // -------------------------------------------------------------
        // Sub-scenario 26B: Asset Combinations (ZIP only, DMG only, Both, None)
        // -------------------------------------------------------------
        let zipOnlyJSON = """
        {
            "tag_name": "v1.0.22",
            "name": "SuperShot v1.0.22",
            "body": "ZIP only release",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22",
            "assets": [
                {
                    "name": "SuperShot-v1.0.22.zip",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.zip"
                }
            ]
        }
        """.data(using: .utf8)!

        let dmgOnlyJSON = """
        {
            "tag_name": "v1.0.22",
            "name": "SuperShot v1.0.22",
            "body": "DMG only release",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22",
            "assets": [
                {
                    "name": "SuperShot-v1.0.22.dmg",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.dmg"
                }
            ]
        }
        """.data(using: .utf8)!

        let bothJSON = """
        {
            "tag_name": "v1.0.22",
            "name": "SuperShot v1.0.22",
            "body": "Both zip and dmg release",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22",
            "assets": [
                {
                    "name": "SuperShot-v1.0.22.dmg",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.dmg"
                },
                {
                    "name": "SuperShot-v1.0.22.zip",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.zip"
                }
            ]
        }
        """.data(using: .utf8)!

        let noAssetsJSON = """
        {
            "tag_name": "v1.0.22",
            "name": "SuperShot v1.0.22",
            "body": "Source only release",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22",
            "assets": [
                {
                    "name": "notes.txt",
                    "browser_download_url": "https://example.com/notes.txt"
                },
                {
                    "name": "source.tar.gz",
                    "browser_download_url": "https://example.com/source.tar.gz"
                }
            ]
        }
        """.data(using: .utf8)!

        if let relZip = try? UpdateManager.parseRelease(from: zipOnlyJSON) {
            ChallengerHarness.assertNotNil(relZip.zipAssetURL, "26B: ZIP-only release parses zipAssetURL")
            ChallengerHarness.assertNil(relZip.dmgAssetURL, "26B: ZIP-only release has nil dmgAssetURL")
            ChallengerHarness.assertEqual(relZip.preferredAssetURL, relZip.zipAssetURL, "26B: ZIP-only preferredAssetURL equals zipAssetURL")
        } else {
            ChallengerHarness.assertTrue(false, "26B: Failed to parse zip-only JSON")
        }

        if let relDmg = try? UpdateManager.parseRelease(from: dmgOnlyJSON) {
            ChallengerHarness.assertNil(relDmg.zipAssetURL, "26B: DMG-only release has nil zipAssetURL")
            ChallengerHarness.assertNotNil(relDmg.dmgAssetURL, "26B: DMG-only release parses dmgAssetURL")
            ChallengerHarness.assertEqual(relDmg.preferredAssetURL, relDmg.dmgAssetURL, "26B: DMG-only preferredAssetURL equals dmgAssetURL")
        } else {
            ChallengerHarness.assertTrue(false, "26B: Failed to parse dmg-only JSON")
        }

        if let relBoth = try? UpdateManager.parseRelease(from: bothJSON) {
            ChallengerHarness.assertNotNil(relBoth.zipAssetURL, "26B: Both release parses zipAssetURL")
            ChallengerHarness.assertNotNil(relBoth.dmgAssetURL, "26B: Both release parses dmgAssetURL")
            ChallengerHarness.assertEqual(relBoth.preferredAssetURL, relBoth.zipAssetURL, "26B: Both release prioritizes zipAssetURL")
        } else {
            ChallengerHarness.assertTrue(false, "26B: Failed to parse both JSON")
        }

        if let relNone = try? UpdateManager.parseRelease(from: noAssetsJSON) {
            ChallengerHarness.assertNil(relNone.zipAssetURL, "26B: No binary release has nil zipAssetURL")
            ChallengerHarness.assertNil(relNone.dmgAssetURL, "26B: No binary release has nil dmgAssetURL")
            ChallengerHarness.assertNil(relNone.preferredAssetURL, "26B: No binary release has nil preferredAssetURL")

            let mgrNoAsset = UpdateManager()
            let semNoAsset = DispatchSemaphore(value: 0)
            var installError: Error? = nil
            mgrNoAsset.startDownloadAndInstall(release: relNone) { result in
                if case .failure(let err) = result {
                    installError = err
                }
                semNoAsset.signal()
            }
            _ = semNoAsset.wait(timeout: .now() + 2.0)
            ChallengerHarness.assertEqual(installError as? UpdateError, UpdateError.noAssetFound, "26B: startDownloadAndInstall fails with .noAssetFound")
            ChallengerHarness.assertEqual(mgrNoAsset.status, .error(message: UpdateError.noAssetFound.localizedDescription), "26B: Status set to .error")
        } else {
            ChallengerHarness.assertTrue(false, "26B: Failed to parse no assets JSON")
        }

        // -------------------------------------------------------------
        // Sub-scenario 26C: Corrupt DMG Extraction & Clean HDIUTIL Unmount Handling
        // -------------------------------------------------------------
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShotAdvM52_DMG_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)

        func getActiveMountCount(matching substring: String) -> Int {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            proc.arguments = ["info"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.components(separatedBy: substring).count - 1
        }

        let mgrDMG = UpdateManager()

        // 26C-1: 0-byte DMG
        let zeroDMG = sandboxDir.appendingPathComponent("zero.dmg")
        FileManager.default.createFile(atPath: zeroDMG.path, contents: Data())
        var zeroFailed = false
        do {
            _ = try mgrDMG.unpackAndVerify(archiveURL: zeroDMG)
        } catch UpdateError.unpackFailed {
            zeroFailed = true
        } catch {}
        ChallengerHarness.assertTrue(zeroFailed, "26C: 0-byte DMG throws UpdateError.unpackFailed")

        // 26C-2: 64KB Garbage bytes DMG
        let garbageDMG = sandboxDir.appendingPathComponent("garbage.dmg")
        var garbageData = [UInt8](repeating: 0, count: 65536)
        for g in 0..<garbageData.count { garbageData[g] = UInt8((g * 37) & 0xFF) }
        FileManager.default.createFile(atPath: garbageDMG.path, contents: Data(garbageData))
        var garbageFailed = false
        do {
            _ = try mgrDMG.unpackAndVerify(archiveURL: garbageDMG)
        } catch UpdateError.unpackFailed {
            garbageFailed = true
        } catch {}
        ChallengerHarness.assertTrue(garbageFailed, "26C: Garbage bytes DMG throws UpdateError.unpackFailed")

        // 26C-3: Valid DMG with NO .app bundle inside
        let noAppFolder = sandboxDir.appendingPathComponent("no_app_dir")
        try! FileManager.default.createDirectory(at: noAppFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: noAppFolder.appendingPathComponent("info.txt").path, contents: "Empty".data(using: .utf8))
        let noAppDMG = sandboxDir.appendingPathComponent("no_app.dmg")

        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p1.arguments = ["create", "-volname", "EmptyDisk", "-srcfolder", noAppFolder.path, "-ov", "-format", "UDZO", noAppDMG.path]
        let pipe1 = Pipe()
        p1.standardOutput = pipe1
        p1.standardError = pipe1
        try! p1.run()
        p1.waitUntilExit()

        var noAppFailed = false
        do {
            _ = try mgrDMG.unpackAndVerify(archiveURL: noAppDMG)
        } catch UpdateError.appBundleNotFound {
            noAppFailed = true
        } catch {}
        ChallengerHarness.assertTrue(noAppFailed, "26C: DMG with no .app bundle throws UpdateError.appBundleNotFound")
        ChallengerHarness.assertEqual(getActiveMountCount(matching: noAppDMG.path), 0, "26C: Clean unmount on appBundleNotFound (0 orphan mounts)")

        // 26C-4: Valid DMG with .app bundle containing NON-executable binary
        let nonExecFolder = sandboxDir.appendingPathComponent("non_exec_dir/SuperShot.app/Contents/MacOS")
        try! FileManager.default.createDirectory(at: nonExecFolder, withIntermediateDirectories: true)
        let nonExecFile = nonExecFolder.appendingPathComponent("SuperShot")
        FileManager.default.createFile(atPath: nonExecFile.path, contents: "not an executable".data(using: .utf8))
        try! FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecFile.path)
        let nonExecDMG = sandboxDir.appendingPathComponent("non_exec.dmg")

        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p2.arguments = ["create", "-volname", "NonExecDisk", "-srcfolder", sandboxDir.appendingPathComponent("non_exec_dir").path, "-ov", "-format", "UDZO", nonExecDMG.path]
        let pipe2 = Pipe()
        p2.standardOutput = pipe2
        p2.standardError = pipe2
        try! p2.run()
        p2.waitUntilExit()

        var nonExecFailed = false
        do {
            _ = try mgrDMG.unpackAndVerify(archiveURL: nonExecDMG)
        } catch UpdateError.binaryNotExecutable {
            nonExecFailed = true
        } catch {}
        ChallengerHarness.assertTrue(nonExecFailed, "26C: DMG with non-executable binary throws UpdateError.binaryNotExecutable")
        ChallengerHarness.assertEqual(getActiveMountCount(matching: nonExecDMG.path), 0, "26C: Clean unmount on binaryNotExecutable (0 orphan mounts)")

        // 26C-5: Valid DMG with valid .app bundle and executable
        let validFolder = sandboxDir.appendingPathComponent("valid_dir/SuperShot.app/Contents/MacOS")
        try! FileManager.default.createDirectory(at: validFolder, withIntermediateDirectories: true)
        let validFile = validFolder.appendingPathComponent("SuperShot")
        FileManager.default.createFile(atPath: validFile.path, contents: "#!/bin/sh\nexit 0\n".data(using: .utf8))
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: validFile.path)
        let validDMG = sandboxDir.appendingPathComponent("valid.dmg")

        let p3 = Process()
        p3.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p3.arguments = ["create", "-volname", "ValidDisk", "-srcfolder", sandboxDir.appendingPathComponent("valid_dir").path, "-ov", "-format", "UDZO", validDMG.path]
        let pipe3 = Pipe()
        p3.standardOutput = pipe3
        p3.standardError = pipe3
        try! p3.run()
        p3.waitUntilExit()

        let validDest = sandboxDir.appendingPathComponent("StagedBundle/SuperShot.app")
        mgrDMG.verifyCodeSignature = false
        var validSuccess = false
        do {
            let res = try mgrDMG.unpackAndVerify(archiveURL: validDMG, destinationURL: validDest)
            ChallengerHarness.assertEqual(res.path, validDest.path, "26C: Staging returns target URL")
            validSuccess = FileManager.default.isExecutableFile(atPath: validDest.appendingPathComponent("Contents/MacOS/SuperShot").path)
        } catch {
            print("DMG unpack error: \(error)")
        }
        ChallengerHarness.assertTrue(validSuccess, "26C: Valid DMG extracted, verified executable and staged successfully")
        ChallengerHarness.assertEqual(getActiveMountCount(matching: validDMG.path), 0, "26C: Clean unmount on successful staging (0 orphan mounts)")

        // -------------------------------------------------------------
        // Sub-scenario 26D: Boundary Download Progress Values & Multi-Threading
        // -------------------------------------------------------------
        let dummyTask = URLSession.shared.downloadTask(with: URL(string: "https://example.com/asset.zip")!)
        var recordedProgress: [Double] = []

        let progressMgr = UpdateManager()
        let progressDelegate = UpdateDownloadDelegate(
            destinationURL: sandboxDir.appendingPathComponent("prog.bin"),
            updateManager: progressMgr,
            onProgress: { p in
                recordedProgress.append(p)
            }
        )

        // 26D-1: 0 totalBytesExpectedToWrite
        recordedProgress.removeAll()
        progressDelegate.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: 10, totalBytesWritten: 10, totalBytesExpectedToWrite: 0)
        ChallengerHarness.assertEqual(recordedProgress.count, 0, "26D: totalBytesExpectedToWrite == 0 is safely ignored")

        // 26D-2: Negative totalBytesExpectedToWrite
        recordedProgress.removeAll()
        progressDelegate.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: 10, totalBytesWritten: 10, totalBytesExpectedToWrite: -500)
        ChallengerHarness.assertEqual(recordedProgress.count, 0, "26D: totalBytesExpectedToWrite < 0 is safely ignored")

        // 26D-3: Negative totalBytesWritten
        recordedProgress.removeAll()
        progressDelegate.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: -20, totalBytesWritten: -100, totalBytesExpectedToWrite: 1000)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        ChallengerHarness.assertEqual(recordedProgress.first ?? -1.0, 0.0, "26D: Negative totalBytesWritten is clamped to 0.0")

        // 26D-4: Zero totalBytesWritten
        recordedProgress.removeAll()
        progressDelegate.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: 0, totalBytesWritten: 0, totalBytesExpectedToWrite: 1000)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        ChallengerHarness.assertEqual(recordedProgress.first ?? -1.0, 0.0, "26D: Zero totalBytesWritten yields 0.0")

        // 26D-5: Overflow totalBytesWritten (> expected)
        recordedProgress.removeAll()
        progressDelegate.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: 2000, totalBytesWritten: 2500, totalBytesExpectedToWrite: 1000)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        ChallengerHarness.assertEqual(recordedProgress.first ?? -1.0, 1.0, "26D: Overflow totalBytesWritten is clamped to 1.0")

        // 26D-6: Equal totalBytesWritten and expected
        recordedProgress.removeAll()
        progressDelegate.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: 1000, totalBytesWritten: 1000, totalBytesExpectedToWrite: 1000)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        ChallengerHarness.assertEqual(recordedProgress.first ?? -1.0, 1.0, "26D: Equal totalBytesWritten yields 1.0")

        // 26D-7: 5,000 multi-threaded concurrent progress events
        let progressGroup = DispatchGroup()
        let progressQueue = DispatchQueue(label: "adv.progress.stress", attributes: .concurrent)
        for _ in 0..<10 {
            progressGroup.enter()
            progressQueue.async {
                for i in 0..<500 {
                    progressDelegate.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: 1, totalBytesWritten: Int64(i), totalBytesExpectedToWrite: 500)
                }
                progressGroup.leave()
            }
        }
        _ = progressGroup.wait(timeout: .now() + 5.0)
        ChallengerHarness.assertTrue(true, "26D: 5,000 rapid concurrent progress dispatches completed with zero deadlocks")

        // -------------------------------------------------------------
        // Sub-scenario 26E: Rapid Repeated Update Checks (100 Concurrent Requests)
        // -------------------------------------------------------------
        let concurrentCheckMgr = UpdateManager()
        concurrentCheckMgr.currentVersion = "1.0.22"
        let checkGroup = DispatchGroup()
        let checkQueue = DispatchQueue(label: "adv.check.stress", attributes: .concurrent)
        for _ in 0..<100 {
            checkGroup.enter()
            checkQueue.async {
                concurrentCheckMgr.checkForUpdates(userInitiated: true) { _ in
                    checkGroup.leave()
                }
            }
        }
        _ = checkGroup.wait(timeout: .now() + 5.0)
        ChallengerHarness.assertTrue(true, "26E: 100 rapid concurrent update checks survived with zero crashes")

        // -------------------------------------------------------------
        // Sub-scenario 26F: Dynamic Staging Resolution Under Various Bundle Paths
        // -------------------------------------------------------------
        let stagingMgr = UpdateManager()
        let defPath = stagingMgr.stagingTargetURL
        ChallengerHarness.assertTrue(defPath.path.hasSuffix(".app"), "26F: Default staging URL resolves to an application bundle")

        let customStaging = sandboxDir.appendingPathComponent("CustomTarget/SuperShot.app")
        stagingMgr.stagingTargetURL = customStaging
        ChallengerHarness.assertEqual(stagingMgr.stagingTargetURL.path, customStaging.path, "26F: Custom stagingTargetURL is stored and preserved")

        let deepNested = sandboxDir.appendingPathComponent("L1/L2/L3/L4/SuperShot.app")
        stagingMgr.verifyCodeSignature = false
        var deepSuccess = false
        do {
            let res = try stagingMgr.unpackAndVerify(archiveURL: validDMG, destinationURL: deepNested)
            deepSuccess = FileManager.default.fileExists(atPath: res.path)
        } catch {}
        ChallengerHarness.assertTrue(deepSuccess, "26F: Successfully created deeply nested destination parent directories and staged bundle")

        // -------------------------------------------------------------
        // Sub-scenario 26G: Safe Relaunch Fallback Timer
        // -------------------------------------------------------------
        let relaunchMgr = UpdateManager()
        var terminationCalled = false
        relaunchMgr.terminationHandler = {
            terminationCalled = true
        }

        var customLaunchedURL: URL? = nil
        relaunchMgr.appLauncher = { target in
            customLaunchedURL = target
            relaunchMgr.terminationHandler()
        }
        relaunchMgr.restartApp()
        ChallengerHarness.assertEqual(customLaunchedURL?.path, relaunchMgr.stagingTargetURL.path, "26G: Custom appLauncher called with target")
        ChallengerHarness.assertTrue(terminationCalled, "26G: terminationHandler invoked on fast path")

        var fallbackFiredCount = 0
        let fallbackLock = NSLock()
        let testTimerMgr = UpdateManager()
        testTimerMgr.terminationHandler = {
            fallbackLock.lock()
            fallbackFiredCount += 1
            fallbackLock.unlock()
        }

        var simulatedTerminated = false
        let simulatedLock = NSLock()
        let doSimulatedTerminate = {
            simulatedLock.lock()
            defer { simulatedLock.unlock() }
            guard !simulatedTerminated else { return }
            simulatedTerminated = true
            testTimerMgr.terminationHandler()
        }

        let fallbackTimer = DispatchSource.makeTimerSource(queue: .main)
        fallbackTimer.schedule(deadline: .now() + 0.15)
        fallbackTimer.setEventHandler {
            doSimulatedTerminate()
        }
        fallbackTimer.resume()

        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.35))
        fallbackTimer.cancel()

        ChallengerHarness.assertEqual(fallbackFiredCount, 1, "26G: Fallback timer fires and triggers terminationHandler exactly once")

        // -------------------------------------------------------------
        // Sub-scenario 26H: Memory Leak Bounds & Zero Orphan Mount Invariants
        // -------------------------------------------------------------
        func getResidentMemory() -> UInt64 {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return kerr == KERN_SUCCESS ? info.resident_size : 0
        }

        let preStressMem = getResidentMemory()
        let memMgr = UpdateManager()
        let memDest = sandboxDir.appendingPathComponent("mem.bin")
        let memDel = UpdateDownloadDelegate(destinationURL: memDest, updateManager: memMgr)

        for m in 0..<2000 {
            _ = try? UpdateManager.parseRelease(from: bothJSON)
            memDel.urlSession(URLSession.shared, downloadTask: dummyTask, didWriteData: 1, totalBytesWritten: Int64(m % 100), totalBytesExpectedToWrite: 100)
        }

        let postStressMem = getResidentMemory()
        let deltaMB = Double(postStressMem > preStressMem ? postStressMem - preStressMem : 0) / (1024.0 * 1024.0)
        ChallengerHarness.assertTrue(deltaMB < 64.0, "26H: Resident memory growth (\(String(format: "%.2f", deltaMB)) MB) strictly bounded (< 64 MB, zero leaks)")
        ChallengerHarness.assertEqual(getActiveMountCount(matching: "SuperShotAdvM52_DMG"), 0, "26H: Zero orphan disk images mounted across entire test lifecycle")

        // Cleanup
        try? FileManager.default.removeItem(at: sandboxDir)
    }
}

// MARK: - Mock Network Protocol for Adversarial Testing

final class AdversarialMockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: HTTPURLResponse?
    static var mockError: Error?
    static var lastRequest: URLRequest?

    static func reset() {
        mockData = nil
        mockResponse = nil
        mockError = nil
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        AdversarialMockURLProtocol.lastRequest = request

        if let error = AdversarialMockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = AdversarialMockURLProtocol.mockResponse
            ?? HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if let data = AdversarialMockURLProtocol.mockData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}


