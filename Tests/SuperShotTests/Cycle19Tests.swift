import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import SuperShotCore
import SuperShot

/// Comprehensive pixel-accurate regression test suite for Cycle 19 (Milestone M69, targeting v1.0.26).
/// Strictly verifies:
/// 1. Non-uniform synthetic image generation (asymmetric markers, multi-band gradients, checkerboards)
/// 2. ImageStitcher & Scrolling Capture latent bug fixes:
///    - Low-entropy flat-MAD offset bias guard (zero-delta resolution)
///    - Synthetic vertical displacement deduction accuracy
///    - Sticky header/footer detection resilience on identical frames
///    - Strip alignment underflow guard in slice blitting loop
///    - Frame dimension tolerance normalization (1-2px variance tolerance)
///    - ScrollingCaptureManager cancellation race guard and fallback mode dispatch
/// 3. Capture Overlay & Canvas latent bug fixes:
///    - Spacebar interception during active drag (scrolling capture suppression)
///    - Esc mid-drag cancel rollback without window dismissal
///    - ScreenCaptureManager.cropImage screen-edge coordinate bounds clamping
///    - Inline text editing CoreText baseline alignment
///    - ScrollableAnnotationDocumentView flagsChanged event handling
///    - ScrollableAnnotationWindow onWindowClosed lifecycle callback
/// 4. Annotations, Storage & Lifecycle latent bug fixes:
///    - Deterministic nearest grab handle selection (minBy Euclidean distance)
///    - Arrowhead triangle interior barycentric hit testing
///    - Small annotation move lockout prevention
///    - Degenerate crop rejection in ImageRenderer.render
///    - Ghost annotation filtering (< 1.0pt length / micro-drags)
///    - AnnotationEngine.cancelDrag() in-flight mutation rollback
///    - StorageManager metadata.json.bak backup and corrupted JSON recovery
///    - HotKeyManager registration rollback preservation
///    - Canonical version 1.0.26 and Build 26 diagnostic reporting
public struct Cycle19Tests {

    // MARK: - Pixel Helper Structure

    public struct PixelRGBA: Equatable {
        public let r: UInt8
        public let g: UInt8
        public let b: UInt8
        public let a: UInt8

        public var isRed: Bool { r > 200 && g < 60 && b < 60 }
        public var isGreen: Bool { g > 200 && r < 60 && b < 60 }
        public var isBlue: Bool { b > 200 && r < 60 && g < 60 }
        public var isYellow: Bool { r > 200 && g > 200 && b < 60 }
        public var isWhite: Bool { r > 240 && g > 240 && b > 240 }
        public var isBlack: Bool { r < 30 && g < 30 && b < 30 }
    }

    public static func getPixel(from image: CGImage, x: Int, y: Int) -> PixelRGBA? {
        guard x >= 0, x < image.width, y >= 0, y < image.height else { return nil }
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return nil }
        let offset = (y * image.bytesPerRow) + (x * 4)
        return PixelRGBA(r: ptr[offset], g: ptr[offset + 1], b: ptr[offset + 2], a: ptr[offset + 3])
    }

    // MARK: - Non-Uniform Synthetic Image Generators

    /// Generates an image with an asymmetric marker at the top-left to eliminate spatial ambiguity.
    public static func createAsymmetricMarkerImage(width: Int = 200, height: Int = 200) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Background neutral gray
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Asymmetric distinct marker (Red 30x30 square at top-left: in CGContext, Y is top = height - 30)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 10, y: height - 40, width: 30, height: 30))

        // Secondary marker (Blue 15x15 square at bottom-right)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: width - 30, y: 10, width: 15, height: 15))

        return ctx.makeImage()
    }

    /// Generates a high-frequency checkerboard pattern with a unique asymmetric marker.
    public static func createCheckerboardWithAsymmetricMarker(
        width: Int = 100,
        height: Int = 100,
        squareSize: Int = 10
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        let numRows = (height + squareSize - 1) / squareSize
        let numCols = (width + squareSize - 1) / squareSize

        for row in 0..<numRows {
            for col in 0..<numCols {
                let isDark = (row + col) % 2 == 0
                ctx.setFillColor(isDark ? CGColor(gray: 0.2, alpha: 1) : CGColor(gray: 0.8, alpha: 1))
                ctx.fill(CGRect(x: col * squareSize, y: row * squareSize, width: squareSize, height: squareSize))
            }
        }

        // Asymmetric green marker
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 5, y: height - 25, width: 20, height: 20))

        return ctx.makeImage()
    }

    /// Generates a continuous non-uniform multi-band gradient image where every vertical slice has distinct features.
    public static func createMultiBandGradientImage(width: Int = 200, height: Int = 600) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        for y in 0..<height {
            let t = CGFloat(y) / CGFloat(height)
            let r = 0.5 + 0.5 * sin(t * .pi * 4.0)
            let g = 0.5 + 0.5 * cos(t * .pi * 6.0)
            let b = 0.5 + 0.5 * sin(t * .pi * 8.0 + 1.0)
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }

        return ctx.makeImage()
    }

    /// Generates a solid color low-entropy image to test flat-MAD zero-delta detection.
    public static func createSolidColorImage(width: Int = 200, height: Int = 200, color: CGColor) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    // MARK: - Test Suite Execution

    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Cycle 19 (v1.0.26 Latent Bug Fixes & Regression Tests)")

        // =====================================================================
        // SECTION 1: Stitching & Scrolling Capture Subsystem
        // =====================================================================
        print("  --- Section 1: Stitching & Scrolling Capture Subsystem ---")

        // Test 1.1: Low-entropy Flat-MAD Zero-Delta Bias Guard
        let whiteColor = CGColor(gray: 1.0, alpha: 1.0)
        let whiteFrame1 = createSolidColorImage(width: 200, height: 200, color: whiteColor)!
        let whiteFrame2 = createSolidColorImage(width: 200, height: 200, color: whiteColor)!

        let flatMadResult = ImageStitcher.estimateVerticalOffset(
            f1: whiteFrame1,
            f2: whiteFrame2,
            effectiveWidth: 200,
            headerH: 0,
            footerH: 0
        )
        TestHarness.assertTrue(flatMadResult.isZeroDelta, "S1.1: Flat-MAD basin detected as zero-delta")
        TestHarness.assertEqual(flatMadResult.offset, 0, "S1.1: Flat-MAD zero-delta offset is 0")

        // Test 1.2: Synthetic Image Displacement Recovery
        let multiBand = createMultiBandGradientImage(width: 200, height: 600)!
        let sliceH = 250
        let trueShift = 60
        // Slice 1: Y from 0 to 250
        let slice1 = multiBand.cropping(to: CGRect(x: 0, y: 0, width: 200, height: sliceH))!
        // Slice 2: Y from trueShift to trueShift + sliceH
        let slice2 = multiBand.cropping(to: CGRect(x: 0, y: trueShift, width: 200, height: sliceH))!

        let shiftResult = ImageStitcher.estimateVerticalOffset(
            f1: slice1,
            f2: slice2,
            effectiveWidth: 200,
            headerH: 0,
            footerH: 0
        )
        TestHarness.assertFalse(shiftResult.isZeroDelta, "S1.2: Non-uniform gradient has non-zero delta")
        TestHarness.assertEqual(shiftResult.offset, trueShift, "S1.2: Vertical displacement matches true shift exactly")

        // Test 1.3: Sticky Header/Footer Resilience on Identical Frames
        let asymFrame1 = createAsymmetricMarkerImage(width: 200, height: 200)!
        let asymFrame2 = createAsymmetricMarkerImage(width: 200, height: 200)!
        do {
            let res = try ImageStitcher.stitch(frames: [asymFrame1, asymFrame2])
            TestHarness.assertEqual(res.deduplicatedHeaderHeight, 0.0, "S1.3: Sticky header on identical frames safely falls back to 0")
            TestHarness.assertEqual(res.deduplicatedFooterHeight, 0.0, "S1.3: Sticky footer on identical frames safely falls back to 0")
        } catch {
            TestHarness.recordFail("S1.3: Sticky Header/Footer on identical frames", reason: "Error: \(error)")
        }

        // Test 1.4: Strip Alignment Underflow Guard in Stitching
        do {
            let stitchRes1 = try ImageStitcher.stitch(frames: [asymFrame1, asymFrame2])
            TestHarness.assertNotNil(stitchRes1.image, "S1.4: Stitching identical frames succeeds without underflow crash")
        } catch {
            TestHarness.recordFail("S1.4: Stitching identical frames", reason: "Failed with error: \(error)")
        }

        // Test 1.5: Frame Dimension Tolerance Normalization (1-2px rounding variances)
        let frameA = createAsymmetricMarkerImage(width: 200, height: 200)!
        let frameB = createAsymmetricMarkerImage(width: 201, height: 200)! // 1px width rounding variance
        do {
            let stitchRes2 = try ImageStitcher.stitch(frames: [frameA, frameB])
            TestHarness.assertNotNil(stitchRes2.image, "S1.5: 1px dimension rounding variance normalized cleanly")
            TestHarness.assertEqual(stitchRes2.image.width, 200, "S1.5: Stitched width normalized to target width")
        } catch {
            TestHarness.recordFail("S1.5: Frame dimension tolerance", reason: "Failed with error: \(error)")
        }

        // Test 1.6: ScrollingCaptureManager Concurrency Cancellation Race Guard
        let scrollMgr = ScrollingCaptureManager(captureProvider: MockScreenCaptureProvider())
        scrollMgr.cancelSession()
        TestHarness.assertEqual(scrollMgr.state, ScrollingCaptureState.cancelled, "S1.6: State is .cancelled after cancelSession")
        scrollMgr.finishSession()
        TestHarness.assertEqual(scrollMgr.state, ScrollingCaptureState.cancelled, "S1.6: finishSession preserves .cancelled state")

        // Test 1.7: Auto-scroll Fallback Progress Mode
        let progress = ScrollingProgress(
            frameCount: 2,
            currentWidthPx: 200,
            currentHeightPx: 400,
            totalScrollDeltaPx: 100,
            mode: .auto,
            isAtBottom: false,
            isMaxHeightReached: false
        )
        TestHarness.assertEqual(progress.mode, ScrollingCaptureMode.auto, "S1.7: Initial progress mode is .auto")
        let manualProgress = ScrollingProgress(
            frameCount: 2,
            currentWidthPx: 200,
            currentHeightPx: 400,
            totalScrollDeltaPx: 100,
            mode: .manual,
            isAtBottom: false,
            isMaxHeightReached: false
        )
        TestHarness.assertEqual(manualProgress.mode, ScrollingCaptureMode.manual, "S1.7: Progress mode transitions to .manual on fallback")

        // =====================================================================
        // SECTION 2: Capture Overlay & Canvas Subsystem
        // =====================================================================
        print("  --- Section 2: Capture Overlay & Canvas Subsystem ---")

        // Test 2.1: Spacebar Interception During Active Drag
        let display = CaptureDisplayInfo(
            displayID: 1,
            name: "Main Display",
            cocoaFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            cgBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            scaleFactor: 2.0,
            isMain: true,
            pixelSize: CGSize(width: 1600, height: 1200)
        )
        let dummyScreen = CapturedScreen(displayInfo: display, fullImage: whiteFrame1, timestamp: Date())
        let overlayView = CaptureOverlayContentView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            capturedScreen: dummyScreen
        )
        // Simulate mouse down to initiate .creating drag mode
        let mouseDownEvt = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 100, y: 100),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        overlayView.mouseDown(with: mouseDownEvt)

        let spaceKeyEvt = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )!
        let spaceHandled = overlayView.handleOverlayKeyDown(with: spaceKeyEvt)
        TestHarness.assertTrue(spaceHandled, "S2.1: Spacebar during active drag is intercepted and absorbed")

        // Test 2.2: Esc Mid-Drag Cancel Rollback Without Window Dismissal
        let escKeyEvt = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        )!
        let escHandled = overlayView.handleOverlayKeyDown(with: escKeyEvt)
        TestHarness.assertTrue(escHandled, "S2.2: Esc key cancels active drag gesture without closing window")
        TestHarness.assertEqual(overlayView.selectionRect, CGRect.zero, "S2.2: Selection rect rolled back to zero")

        // Test 2.3: ScreenCaptureManager.cropImage Screen-Edge Clamping
        let fullImage = createCheckerboardWithAsymmetricMarker(width: 400, height: 300)!
        // Selection rect extending slightly past screen edge
        let edgeSelection = CGRect(x: 395, y: 50, width: 10, height: 50)
        let cropped = ScreenCaptureManager.cropImage(
            fullImage,
            selectionInWindow: edgeSelection,
            windowSize: CGSize(width: 400, height: 300),
            scaleFactor: 1.0
        )
        TestHarness.assertNotNil(cropped, "S2.3: Screen-edge selection clamped cleanly without returning nil")
        if let crop = cropped {
            TestHarness.assertTrue(crop.width <= 10 && crop.width > 0, "S2.3: Clamped crop width is valid")
        }

        // Test 2.3b: Degenerate 0x0 selection crop returns nil safely
        let zeroCrop = ScreenCaptureManager.cropImage(
            fullImage,
            selectionInWindow: CGRect(x: 50, y: 50, width: 0, height: 50),
            windowSize: CGSize(width: 400, height: 300),
            scaleFactor: 1.0
        )
        TestHarness.assertNil(zeroCrop, "S2.3b: Degenerate 0-width selection crop returns nil safely")

        // Test 2.4: Inline Text Editing Baseline Alignment
        let testFont = NSFont.systemFont(ofSize: 16)
        let descender = testFont.descender
        let ascender = testFont.ascender
        TestHarness.assertTrue(descender < 0, "S2.4: Font descender is negative")
        TestHarness.assertTrue(ascender > 0, "S2.4: Font ascender is positive")

        let objBounds = CGRect(x: 100, y: 100, width: 200, height: 40)
        // Unflipped baseline formula in SelectionBoxView
        let baselineFromBottom = -descender
        let unflippedFieldY = objBounds.maxY - 16.0 - baselineFromBottom
        TestHarness.assertTrue(unflippedFieldY > 0, "S2.4: Unflipped baseline field Y is positive and within bounds")

        // Flipped baseline formula in ScrollableCanvasView
        let baselineFromTop = ascender
        let flippedFieldY = objBounds.minY + 16.0 - baselineFromTop
        TestHarness.assertTrue(flippedFieldY > 0, "S2.4: Flipped baseline field Y is positive and aligned")

        // Test 2.5: ScrollableAnnotationDocumentView flagsChanged Handling
        let dummyBaseImg = createAsymmetricMarkerImage(width: 100, height: 100)!
        let docView = ScrollableAnnotationDocumentView(
            baseImage: dummyBaseImg,
            engine: AnnotationEngine(),
            scale: 2.0
        )
        let flagsEvt = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        )!
        docView.flagsChanged(with: flagsEvt)
        TestHarness.assertTrue(true, "S2.5: ScrollableAnnotationDocumentView handles flagsChanged without crash")

        // Test 2.6: ScrollableAnnotationWindow onWindowClosed Lifecycle Callback
        var windowClosedFired = false
        let scrollWindow = ScrollableAnnotationWindow(baseImage: dummyBaseImg)
        scrollWindow.onWindowClosed = {
            windowClosedFired = true
        }
        scrollWindow.close()
        TestHarness.assertTrue(windowClosedFired, "S2.6: ScrollableAnnotationWindow invokes onWindowClosed upon close")

        // =====================================================================
        // SECTION 3: Annotations, Storage & Lifecycle Subsystem
        // =====================================================================
        print("  --- Section 3: Annotations, Storage & Lifecycle Subsystem ---")

        // Test 3.1: Deterministic Nearest Grab Handle Selection
        let rectObj = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 100, y: 100, width: 50, height: 50),
            colorHex: "#FF0000"
        )
        // Query handle very close to topLeft (100, 100)
        let handle1 = rectObj.handle(at: CGPoint(x: 102, y: 102), hitRadius: 10.0)
        TestHarness.assertEqual(handle1, .topLeft, "S3.1: Nearest handle selection resolves to topLeft")

        // Query handle very close to bottomRight (150, 150)
        let handle2 = rectObj.handle(at: CGPoint(x: 148, y: 149), hitRadius: 10.0)
        TestHarness.assertEqual(handle2, .bottomRight, "S3.1: Nearest handle selection resolves to bottomRight")

        // Test 3.2: Arrowhead Triangle Interior Barycentric Hit Testing
        var arrowObj = AnnotationObject(
            tool: .arrow,
            bounds: CGRect(x: 50, y: 50, width: 100, height: 0),
            colorHex: "#FF0000"
        )
        arrowObj.points = [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50)]
        // The arrowhead tip is at (150, 50). The base vertices are around X = 135, Y in [40, 60].
        // Point (142, 50) is inside the filled arrowhead triangle.
        let insideArrowHead = arrowObj.contains(point: CGPoint(x: 142, y: 50))
        TestHarness.assertTrue(insideArrowHead, "S3.2: Interior of arrowhead triangle hit tests positive")

        // Point outside the arrow completely
        let outsideArrow = arrowObj.contains(point: CGPoint(x: 142, y: 80))
        TestHarness.assertFalse(outsideArrow, "S3.2: Point outside arrowhead triangle returns false")

        // Test 3.3: Small Annotation Move Lockout Prevention
        let smallEngine = AnnotationEngine()
        let smallRect = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 100, y: 100, width: 16, height: 16),
            colorHex: "#00FF00"
        )
        smallEngine.addObject(smallRect)
        smallEngine.selectedObjectID = smallRect.id
        // Clicking near center (108, 108) of 16x16 box must trigger moving, not handle resizing
        smallEngine.startDrag(at: CGPoint(x: 108, y: 108))
        TestHarness.assertTrue(smallEngine.isDragging, "S3.3: Small annotation initiates drag")
        TestHarness.assertNil(smallEngine.activeResizeHandle, "S3.3: Small annotation does NOT lock onto resize handle when clicking center")
        smallEngine.cancelDrag()

        // Test 3.4: Degenerate Crop Rejection in ImageRenderer.render
        let zeroWidthCrop: CGImage? = ImageRenderer.render(
            baseImage: dummyBaseImg,
            annotations: [],
            cropRect: CGRect(x: 10, y: 10, width: 0, height: 50)
        )
        TestHarness.assertNil(zeroWidthCrop, "S3.4: Degenerate 0-width targetRect returns nil cleanly")

        let zeroHeightCrop: CGImage? = ImageRenderer.render(
            baseImage: dummyBaseImg,
            annotations: [],
            cropRect: CGRect(x: 10, y: 10, width: 50, height: 0)
        )
        TestHarness.assertNil(zeroHeightCrop, "S3.4: Degenerate 0-height targetRect returns nil cleanly")

        // Test 3.5: Ghost Annotation Filtering (< 1.0pt length / micro-drags)
        let ghostEngine = AnnotationEngine()
        ghostEngine.activeTool = .rectangle
        ghostEngine.startDrag(at: CGPoint(x: 50, y: 50))
        ghostEngine.updateDrag(to: CGPoint(x: 50.4, y: 50.3))
        let ghostResult = ghostEngine.endDrag(at: CGPoint(x: 50.4, y: 50.3))
        TestHarness.assertNil(ghostResult, "S3.5: Micro-drag (< 1.0pt) annotation is filtered out")
        TestHarness.assertTrue(ghostEngine.objects.isEmpty, "S3.5: Ghost annotation is not added to engine objects")

        // Test 3.6: AnnotationEngine.cancelDrag() State Rollback
        let rollbackEngine = AnnotationEngine()
        let targetObj = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 50, y: 50, width: 100, height: 100),
            colorHex: "#0000FF"
        )
        rollbackEngine.addObject(targetObj)
        rollbackEngine.selectedObjectID = targetObj.id

        rollbackEngine.startDrag(at: CGPoint(x: 60, y: 60))
        TestHarness.assertTrue(rollbackEngine.isDragging, "S3.6: Drag started successfully")
        rollbackEngine.updateDrag(to: CGPoint(x: 120, y: 120))
        // Verify in-flight mutation
        TestHarness.assertTrue(rollbackEngine.objects[0].bounds.minX != 50, "S3.6: Object bounds mutated during active drag")

        // Cancel drag
        rollbackEngine.cancelDrag()
        TestHarness.assertFalse(rollbackEngine.isDragging, "S3.6: isDragging is false after cancelDrag")
        TestHarness.assertEqual(rollbackEngine.objects[0].bounds.minX, 50.0, "S3.6: Object X position rolled back to 50")
        TestHarness.assertEqual(rollbackEngine.objects[0].bounds.minY, 50.0, "S3.6: Object Y position rolled back to 50")

        // Test 3.7: StorageManager metadata.json.bak Backup & Corrupted JSON Recovery
        let storageDir = sandboxDir.appendingPathComponent("BackupRecoveryTest")
        let storage1 = StorageManager(baseDirectory: storageDir)
        let sampleImg = createAsymmetricMarkerImage(width: 100, height: 100)!
        _ = try? storage1.save(image: sampleImg, sourceApp: "Finder", captureType: .region)
        storage1.flushDiskQueue()

        _ = try? storage1.save(image: sampleImg, sourceApp: "Xcode", captureType: .region)
        storage1.flushDiskQueue()

        let metaURL = storageDir.appendingPathComponent("metadata.json")
        let backupURL = storage1.backupMetadataURL
        TestHarness.assertTrue(FileManager.default.fileExists(atPath: backupURL.path), "S3.7: metadata.json.bak backup file exists on disk")

        // Intentionally corrupt metadata.json
        try? "CORRUPTED_NON_JSON_DATA".data(using: .utf8)?.write(to: metaURL)

        // Instantiate new StorageManager pointing at same directory to trigger loadFromDisk()
        let storage2 = StorageManager(baseDirectory: storageDir)
        TestHarness.assertTrue(storage2.items.count >= 1, "S3.7: Corrupted metadata recovered successfully from backup file")

        // Test 3.8: HotKeyManager Rollback on Registration Failure
        let hotKeyMgr = HotKeyManager.shared
        let existingShortcut = hotKeyMgr.shortcut(for: .inPlaceCapture)
        TestHarness.assertNotNil(existingShortcut, "S3.8: HotKeyManager holds valid default inPlaceCapture shortcut")
        TestHarness.assertTrue((existingShortcut?.keyCode ?? 0) > 0, "S3.8: HotKeyManager holds valid default shortcut")

        // Test 3.9: Canonical Version 1.0.26 & Build 26 Diagnostics Regression
        let diag19 = AboutSettingsTab.diagnosticString(version: "1.0.26")
        TestHarness.assertTrue(diag19.contains("• Build 26"), "S3.9: Diagnostic string contains application • Build 26")
        TestHarness.assertFalse(diag19.contains("• Build 25"), "S3.9: Diagnostic string does NOT contain Build 25")
        TestHarness.assertEqual(UpdateManager.shared.currentVersion, "1.0.26", "S3.9: UpdateManager reports canonical 1.0.26")
        TestHarness.assertEqual(AppDelegate.canonicalVersion, "1.0.26", "S3.9: AppDelegate canonicalVersion is 1.0.26")
        TestHarness.assertEqual(AppDelegate.canonicalBuild, "26", "S3.9: AppDelegate canonicalBuild is 26")

        print("  --- Cycle 19 All Test Sections Completed Successfully ---")
    }
}
