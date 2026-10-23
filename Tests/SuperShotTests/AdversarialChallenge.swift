import Foundation
import CoreGraphics
import AppKit
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


