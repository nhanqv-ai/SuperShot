import Foundation
import CoreGraphics
import AppKit
import SuperShotCore
import SuperShot

public struct CaptureOverlayTests {
    public static func run() {
        TestHarness.startSuite("Milestone 2: Screen Capture & Overlay Subsystem")

        // 1. Mock ScreenCaptureManager Tests
        testMockScreenCapture()

        // 2. Multi-Display & Coordinate Math Tests
        testCoordinateMath()

        // 3. SelectionBoxGeometry & 8-Handle Hit-Testing Tests
        test8HandleHitTesting()

        // 4. Drag Resizing & Cross-Edge Inversion Tests
        testDragResizingAndInversion()

        // 5. Live Dimension Badge Formatting & Boundary Flipping Tests
        testDimensionBadge()

        // 6. Edge-Aware Toolbar Positioning & Collision Resolution Tests
        testEdgeAwareToolbarPositioning()

        // 7. Crop Image at 2x Retina Resolution Tests
        testRetina2xCropping()

        // 8. Toolbar Boundary Containment & Collision Resolution (Top-Right Corner, Top Edge, Right Edge)
        testToolbarBoundaryContainmentAndCollision()

        // 9. Aspect Ratio Detection & Shift-Key Lock (v1.0.10)
        testAspectRatioAndShiftLock()

        // 10. In-Place Capture Quick Copy Confirmation (v1.0.18)
        testQuickCopyConfirmation()

        // 11. Selection Handle Center-Out & 1:1 Aspect Resizing (v1.0.19)
        test11HandleCenterOutAndAspectResizing()
    }

    // --- Test 1: Mock ScreenCaptureManager ---
    private static func testMockScreenCapture() {
        let mockProvider = MockScreenCaptureProvider()
        let manager = ScreenCaptureManager(provider: mockProvider)

        let displays = mockProvider.availableDisplays()
        TestHarness.assertEqual(displays.count, 2, "Mock provider reports exactly 2 displays")
        TestHarness.assertTrue(displays[0].isMain, "Display 0 is main display")
        TestHarness.assertEqual(displays[0].scaleFactor, 2.0, "Main display is Retina 2x scale")
        TestHarness.assertEqual(displays[1].scaleFactor, 1.0, "Secondary display is 1x scale")

        let captured = manager.captureMainScreen()
        TestHarness.assertNotNil(captured, "Captured main screen is non-nil")
        TestHarness.assertEqual(captured?.fullImage.width, 2880, "Main display captured image width is 2880 px (1440 * 2)")
        TestHarness.assertEqual(captured?.fullImage.height, 1800, "Main display captured image height is 1800 px (900 * 2)")
    }

    // --- Test 2: Multi-Display & Coordinate Math ---
    private static func testCoordinateMath() {
        let mockProvider = MockScreenCaptureProvider()
        let displays = mockProvider.availableDisplays()
        let main = displays[0]
        let secondary = displays[1]

        // Main display point lookup
        let hitMain = mockProvider.display(containing: CGPoint(x: 500, y: 500))
        TestHarness.assertEqual(hitMain?.displayID, main.displayID, "Point (500, 500) resolves to main display")

        // Secondary display point lookup (positioned to the right at x=1440)
        let hitSec = mockProvider.display(containing: CGPoint(x: 1600, y: 200))
        TestHarness.assertEqual(hitSec?.displayID, secondary.displayID, "Point (1600, 200) resolves to secondary display")

        // Cocoa to CoreGraphics coordinate conversion
        let primaryHeight: CGFloat = 900.0
        let cocoaRect = CGRect(x: 100, y: 700, width: 200, height: 100)
        let cgGlobalY = primaryHeight - (cocoaRect.origin.y + cocoaRect.height)
        TestHarness.assertEqual(cgGlobalY, 100.0, "Cocoa y=700 (top edge=800) converts to CG y=100 from top of screen")
    }

    // --- Test 3: SelectionBoxGeometry & 8-Handle Hit Testing ---
    private static func test8HandleHitTesting() {
        let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
        let handles = SelectionBoxGeometry.handlePositions(for: rect)

        TestHarness.assertEqual(handles[.topLeft], CGPoint(x: 100, y: 400), "Top-Left handle at (100, 400)")
        TestHarness.assertEqual(handles[.topCenter], CGPoint(x: 300, y: 400), "Top-Center handle at (300, 400)")
        TestHarness.assertEqual(handles[.topRight], CGPoint(x: 500, y: 400), "Top-Right handle at (500, 400)")
        TestHarness.assertEqual(handles[.middleLeft], CGPoint(x: 100, y: 250), "Middle-Left handle at (100, 250)")
        TestHarness.assertEqual(handles[.middleRight], CGPoint(x: 500, y: 250), "Middle-Right handle at (500, 250)")
        TestHarness.assertEqual(handles[.bottomLeft], CGPoint(x: 100, y: 100), "Bottom-Left handle at (100, 100)")
        TestHarness.assertEqual(handles[.bottomCenter], CGPoint(x: 300, y: 100), "Bottom-Center handle at (300, 100)")
        TestHarness.assertEqual(handles[.bottomRight], CGPoint(x: 500, y: 100), "Bottom-Right handle at (500, 100)")

        // Hit testing handle centers within tolerance (hitRadius = 9pt)
        let hitTL = SelectionBoxGeometry.hitTestHandle(point: CGPoint(x: 102, y: 398), in: rect)
        TestHarness.assertEqual(hitTL, .topLeft, "Hit test detects Top-Left handle within 9pt radius")

        let hitBR = SelectionBoxGeometry.hitTestHandle(point: CGPoint(x: 497, y: 104), in: rect)
        TestHarness.assertEqual(hitBR, .bottomRight, "Hit test detects Bottom-Right handle within 9pt radius")

        let hitCenter = SelectionBoxGeometry.hitTestHandle(point: CGPoint(x: 300, y: 250), in: rect)
        TestHarness.assertNil(hitCenter, "Center of selection is not a handle hit")
    }

    // --- Test 4: Drag Resizing & Cross-Edge Inversion ---
    private static func testDragResizingAndInversion() {
        let screenBounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

        // Normal drag: dragging bottom-right handle
        let anchor = CGPoint(x: 100, y: 400) // Top-Left anchor
        let current = CGPoint(x: 600, y: 200)
        let resized = SelectionBoxGeometry.normalizeRect(p1: anchor, p2: current, bounds: screenBounds)
        TestHarness.assertEqual(resized.minX, 100.0, "Resized minX is 100")
        TestHarness.assertEqual(resized.maxX, 600.0, "Resized maxX is 600")
        TestHarness.assertEqual(resized.minY, 200.0, "Resized minY is 200")
        TestHarness.assertEqual(resized.maxY, 400.0, "Resized maxY is 400")

        // Inversion drag: dragging right handle past left anchor
        let invertedCurrent = CGPoint(x: 50, y: 200) // Left of anchor x=100
        let invertedRect = SelectionBoxGeometry.normalizeRect(p1: anchor, p2: invertedCurrent, bounds: screenBounds)
        TestHarness.assertEqual(invertedRect.minX, 50.0, "Cross-edge inversion swaps minX to 50")
        TestHarness.assertEqual(invertedRect.maxX, 100.0, "Cross-edge inversion sets maxX to anchor 100")
        TestHarness.assertTrue(invertedRect.width > 0, "Inverted rect maintains positive width")
        TestHarness.assertTrue(invertedRect.height > 0, "Inverted rect maintains positive height")

        // Boundary clamp: dragging off-screen
        let offScreenPoint = CGPoint(x: 2000, y: -500)
        let clampedRect = SelectionBoxGeometry.normalizeRect(p1: anchor, p2: offScreenPoint, bounds: screenBounds)
        TestHarness.assertEqual(clampedRect.maxX, 1440.0, "Clamps to right screen bound 1440")
        TestHarness.assertEqual(clampedRect.minY, 0.0, "Clamps to bottom screen bound 0")
    }

    // --- Test 5: Live Dimension Badge Formatting & Boundary Flipping ---
    private static func testDimensionBadge() {
        // Retina 2x scale formatting
        let badgeText2x = SelectionBoxGeometry.formatDimensionBadge(width: 400.5, height: 250.0, scaleFactor: 2.0)
        TestHarness.assertEqual(badgeText2x, "801 x 500 px", "Badge formats Retina 2x dimensions correctly")

        // Standard 1x scale formatting
        let badgeText1x = SelectionBoxGeometry.formatDimensionBadge(width: 320.0, height: 180.0, scaleFactor: 1.0)
        TestHarness.assertEqual(badgeText1x, "320 x 180 px", "Badge formats 1x dimensions correctly")

        // Normal badge placement above selection
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let midSelection = CGRect(x: 200, y: 300, width: 400, height: 200)
        let normalBadge = ToolbarPositionCalculator.calculateDimensionBadgeFrame(selectionRect: midSelection, screenBounds: screen)
        TestHarness.assertEqual(normalBadge.origin.x, 200.0, "Badge origin X aligns with selection minX")
        TestHarness.assertEqual(normalBadge.origin.y, 506.0, "Badge origin Y is above selection maxY (500 + 6)")

        // Top edge collision: flips inside or below selection box
        let topSelection = CGRect(x: 200, y: 800, width: 400, height: 95)
        let flippedBadge = ToolbarPositionCalculator.calculateDimensionBadgeFrame(selectionRect: topSelection, screenBounds: screen)
        TestHarness.assertTrue(flippedBadge.maxY <= 900 - 8, "Badge does not exceed top screen boundary")
        TestHarness.assertTrue(flippedBadge.origin.y < topSelection.maxY, "Badge flipped below selection top edge")

        // Bottom edge collision: horizontal toolbar flips above selection, badge positioned above toolbar
        let bottomSelection = CGRect(x: 200, y: 20, width: 400, height: 100)
        let bottomBadge = ToolbarPositionCalculator.calculateDimensionBadgeFrame(selectionRect: bottomSelection, screenBounds: screen)
        let bottomHoriz = ToolbarPositionCalculator.calculateHorizontalToolbarFrame(selectionRect: bottomSelection, screenBounds: screen)
        TestHarness.assertEqual(bottomBadge.origin.y, bottomHoriz.maxY + 6.0, "Badge positioned above flipped horizontal toolbar")
        TestHarness.assertTrue(bottomBadge.minY >= bottomHoriz.maxY, "Badge does not visually overlap flipped horizontal toolbar")
    }

    // --- Test 6: Edge-Aware Toolbar Positioning & Collision Resolution ---
    private static func testEdgeAwareToolbarPositioning() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        // Case A: Middle of screen -> Vertical on right, Horizontal below
        let midRect = CGRect(x: 400, y: 300, width: 400, height: 300)
        let vertMid = ToolbarPositionCalculator.calculateVerticalToolbarFrame(selectionRect: midRect, screenBounds: screen)
        TestHarness.assertEqual(vertMid.origin.x, 808.0, "Vertical toolbar placed to the right (800 + 8)")
        TestHarness.assertTrue(vertMid.maxX <= screen.maxX, "Vertical toolbar inside screen")

        let horizMid = ToolbarPositionCalculator.calculateHorizontalToolbarFrame(selectionRect: midRect, screenBounds: screen)
        TestHarness.assertEqual(horizMid.origin.y, 300.0 - 8.0 - 36.0, "Horizontal toolbar placed below (300 - 8 - 36 = 256)")
        TestHarness.assertTrue(horizMid.minY >= screen.minY, "Horizontal toolbar inside screen")

        // Case B: Right edge collision -> Vertical toolbar flips to LEFT
        let rightRect = CGRect(x: 1250, y: 300, width: 180, height: 300)
        let vertFlipped = ToolbarPositionCalculator.calculateVerticalToolbarFrame(selectionRect: rightRect, screenBounds: screen)
        TestHarness.assertTrue(vertFlipped.maxX <= rightRect.minX, "Vertical toolbar flipped to the left of selection")
        TestHarness.assertTrue(vertFlipped.minX >= 8.0, "Vertical toolbar maintains minimum 8pt left margin")

        // Case C: Bottom edge collision -> Horizontal toolbar flips to TOP
        let bottomRect = CGRect(x: 400, y: 20, width: 400, height: 300)
        let horizFlipped = ToolbarPositionCalculator.calculateHorizontalToolbarFrame(selectionRect: bottomRect, screenBounds: screen)
        TestHarness.assertTrue(horizFlipped.minY >= bottomRect.maxY, "Horizontal toolbar flipped above selection")

        // Case D: Tiny 20x20 selection box collision prevention
        let tinyRect = CGRect(x: 500, y: 500, width: 20, height: 20)
        let resolved = ToolbarPositionCalculator.resolveToolbarFrames(selectionRect: tinyRect, screenBounds: screen)
        TestHarness.assertFalse(resolved.vertical.intersects(resolved.horizontal), "Toolbars do not overlap on 20x20 selection box")
    }

    // --- Test 7: Crop Image at 2x Retina Resolution ---
    private static func testRetina2xCropping() {
        let mockProvider = MockScreenCaptureProvider()
        let manager = ScreenCaptureManager(provider: mockProvider)
        guard let captured = manager.captureMainScreen() else {
            TestHarness.recordFail("Retina Crop", reason: "captureMainScreen returned nil")
            return
        }

        let selection = CGRect(x: 100, y: 200, width: 200, height: 150)
        let windowSize = CGSize(width: 1440, height: 900)
        let cropped = ScreenCaptureManager.cropImage(
            captured.fullImage,
            selectionInWindow: selection,
            windowSize: windowSize,
            scaleFactor: 2.0
        )

        TestHarness.assertNotNil(cropped, "Cropped image is non-nil")
        TestHarness.assertEqual(cropped?.width, 400, "Cropped image width is 400 physical pixels (200 * 2)")
        TestHarness.assertEqual(cropped?.height, 300, "Cropped image height is 300 physical pixels (150 * 2)")
    }

    // --- Test 8: Regression Test - Toolbar Boundary Containment & Zero Collisions (Top-Right, Top Edge, Right Edge) ---
    private static func testToolbarBoundaryContainmentAndCollision() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let testCases: [(name: String, rect: CGRect)] = [
            // 1. Top-Right Display Corner
            ("Top-Right Corner (1380, 840, 50x50)", CGRect(x: 1380, y: 840, width: 50, height: 50)),
            ("Top-Right Extreme (1430, 890, 10x10)", CGRect(x: 1430, y: 890, width: 10, height: 10)),
            ("Top-Right Apex (1439, 899, 1x1)", CGRect(x: 1439, y: 899, width: 1, height: 1)),

            // 2. Top Edge
            ("Top Edge Small (100, 895, 50x50)", CGRect(x: 100, y: 895, width: 50, height: 50)),
            ("Top Edge Wide (500, 880, 440x20)", CGRect(x: 500, y: 880, width: 440, height: 20)),
            ("Top Edge Flush (700, 860, 100x40)", CGRect(x: 700, y: 860, width: 100, height: 40)),

            // 3. Right Edge
            ("Right Edge Tall (1350, 60, 80x300)", CGRect(x: 1350, y: 60, width: 80, height: 300)),
            ("Right Edge Flush (1400, 60, 40x300)", CGRect(x: 1400, y: 60, width: 40, height: 300)),
            ("Right Edge Mid (1410, 400, 30x50)", CGRect(x: 1410, y: 400, width: 30, height: 50))
        ]

        for (name, rect) in testCases {
            let resolved = ToolbarPositionCalculator.resolveToolbarFrames(selectionRect: rect, screenBounds: screen)

            // Assert 100% containment within screen bounds
            TestHarness.assertTrue(
                screen.contains(resolved.vertical),
                "\(name): Vertical toolbar must be 100% contained within screen bounds (frame: \(resolved.vertical))"
            )
            TestHarness.assertTrue(
                screen.contains(resolved.horizontal),
                "\(name): Horizontal toolbar must be 100% contained within screen bounds (frame: \(resolved.horizontal))"
            )

            // Assert zero collisions between vertical and horizontal toolbars
            TestHarness.assertFalse(
                resolved.vertical.intersects(resolved.horizontal),
                "\(name): Vertical and horizontal toolbars must have 0 collisions (vert: \(resolved.vertical), horiz: \(resolved.horizontal))"
            )

            // Boundary clamping verification
            TestHarness.assertTrue(
                resolved.vertical.minX >= screen.minX && resolved.vertical.maxX <= screen.maxX,
                "\(name): Vertical toolbar X clamped within [\(screen.minX), \(screen.maxX)]"
            )
            TestHarness.assertTrue(
                resolved.vertical.minY >= screen.minY && resolved.vertical.maxY <= screen.maxY,
                "\(name): Vertical toolbar Y clamped within [\(screen.minY), \(screen.maxY)]"
            )
            TestHarness.assertTrue(
                resolved.horizontal.minX >= screen.minX && resolved.horizontal.maxX <= screen.maxX,
                "\(name): Horizontal toolbar X clamped within [\(screen.minX), \(screen.maxX)]"
            )
            TestHarness.assertTrue(
                resolved.horizontal.minY >= screen.minY && resolved.horizontal.maxY <= screen.maxY,
                "\(name): Horizontal toolbar Y clamped within [\(screen.minY), \(screen.maxY)]"
            )
        }
    }

    // --- Test 9: Aspect Ratio Detection, Smart Badge & Shift-Key Lock (v1.0.10) ---
    private static func testAspectRatioAndShiftLock() {
        // 1. Standard Aspect Ratio Detection
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 800, height: 800), "1:1", "Square detects 1:1")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 1920, height: 1080), "16:9", "1920x1080 detects 16:9")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 1024, height: 768), "4:3", "1024x768 detects 4:3")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 1920, height: 1200), "16:10", "1920x1200 detects 16:10")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 1500, height: 1000), "3:2", "1500x1000 detects 3:2")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 2560, height: 1080), "21:9", "2560x1080 detects 21:9")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 1080, height: 1920), "9:16", "1080x1920 detects 9:16")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 768, height: 1024), "3:4", "768x1024 detects 3:4")
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 1000, height: 1500), "2:3", "1000x1500 detects 2:3")

        // 2. Tolerance & Non-standard ratios
        TestHarness.assertEqual(SelectionBoxGeometry.detectAspectRatio(width: 1915, height: 1080), "16:9", "Within 2.5% tolerance detects 16:9")
        TestHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 500, height: 420), "Non-standard ratio returns nil")
        TestHarness.assertNil(SelectionBoxGeometry.detectAspectRatio(width: 5, height: 5), "Dimensions <= 10 return nil")

        // 3. Smart Dimension Badge Formatting
        let badgeWithAspect = SelectionBoxGeometry.formatDimensionBadge(
            width: 1920,
            height: 1080,
            scaleFactor: 1.0,
            includeAspectRatio: true
        )
        TestHarness.assertEqual(badgeWithAspect, "1920 x 1080 px (16:9)", "Badge formats with aspect ratio")

        let badgeSquare2x = SelectionBoxGeometry.formatDimensionBadge(
            width: 400,
            height: 400,
            scaleFactor: 2.0,
            includeAspectRatio: true
        )
        TestHarness.assertEqual(badgeSquare2x, "800 x 800 px (1:1)", "Retina 2x square badge formats 1:1")

        let badgeNoAspect = SelectionBoxGeometry.formatDimensionBadge(
            width: 1920,
            height: 1080,
            scaleFactor: 1.0,
            includeAspectRatio: false
        )
        TestHarness.assertEqual(badgeNoAspect, "1920 x 1080 px", "includeAspectRatio=false preserves raw dimension string")

        // 4. Shift-Key Square Resizing Constraint
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGPoint(x: 100, y: 100)
        let dragPoint = CGPoint(x: 350, y: 200) // dx = 250, dy = 100
        let unconstrainedRect = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: dragPoint,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: false
        )
        TestHarness.assertEqual(unconstrainedRect.width, 250.0, "Unconstrained width is 250")
        TestHarness.assertEqual(unconstrainedRect.height, 100.0, "Unconstrained height is 100")

        let constrainedRect = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: dragPoint,
            anchor: anchor,
            bounds: bounds,
            shiftKeyPressed: true
        )
        TestHarness.assertEqual(constrainedRect.width, 250.0, "Constrained width is 250")
        TestHarness.assertEqual(constrainedRect.height, 250.0, "Constrained height is 250 (1:1 square)")

        // 5. Option-Modifier Center-Out Selection Box Creation
        let center = CGPoint(x: 500, y: 500)
        let target = CGPoint(x: 550, y: 530)
        let centerRect = SelectionBoxGeometry.calculateCenterRect(
            center: center,
            target: target,
            bounds: bounds,
            squareConstrained: false
        )
        TestHarness.assertEqual(centerRect.origin.x, 450.0, "Center-out rect minX is 450 (500 - 50)")
        TestHarness.assertEqual(centerRect.origin.y, 470.0, "Center-out rect minY is 470 (500 - 30)")
        TestHarness.assertEqual(centerRect.width, 100.0, "Center-out rect width is 100 (50 * 2)")
        TestHarness.assertEqual(centerRect.height, 60.0, "Center-out rect height is 60 (30 * 2)")
        TestHarness.assertEqual(centerRect.midX, center.x, "Center-out rect midX matches center point")
        TestHarness.assertEqual(centerRect.midY, center.y, "Center-out rect midY matches center point")

        // 6. Option+Shift Center-Out Square Selection
        let centerSquareRect = SelectionBoxGeometry.calculateCenterRect(
            center: center,
            target: target,
            bounds: bounds,
            squareConstrained: true
        )
        TestHarness.assertEqual(centerSquareRect.origin.x, 450.0, "Center-out square minX is 450 (500 - 50)")
        TestHarness.assertEqual(centerSquareRect.origin.y, 450.0, "Center-out square minY is 450 (500 - 50)")
        TestHarness.assertEqual(centerSquareRect.width, 100.0, "Center-out square width is 100")
        TestHarness.assertEqual(centerSquareRect.height, 100.0, "Center-out square height is 100")
        TestHarness.assertEqual(centerSquareRect.midX, center.x, "Center-out square midX matches center point")
        TestHarness.assertEqual(centerSquareRect.midY, center.y, "Center-out square midY matches center point")
    }

    // --- Test 10: In-Place Capture Quick Copy Confirmation (v1.0.18) ---
    private static func testQuickCopyConfirmation() {
        let display = CaptureDisplayInfo(
            displayID: 1,
            name: "Main",
            cocoaFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            cgBounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scaleFactor: 2.0,
            isMain: true,
            pixelSize: CGSize(width: 2880, height: 1800)
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let dummyImage = ctx.makeImage()!
        let captured = CapturedScreen(displayInfo: display, fullImage: dummyImage)

        let contentView = CaptureOverlayContentView(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            capturedScreen: captured
        )
        contentView.selectionRect = CGRect(x: 100, y: 100, width: 200, height: 150)
        TestHarness.assertTrue(contentView.toolHUDText == nil, "Initial toolHUDText is nil")

        // Trigger onCopyRequested
        contentView.toolbarsViewModel.onCopyRequested?()
        TestHarness.assertEqual(contentView.toolHUDText, LocalizationManager.shared.tr(.copiedToClipboard), "onCopyRequested sets toolHUDText to copiedToClipboard HUD text")
    }

    // --- Test 11: Selection Handle Center-Out & 1:1 Aspect Resizing (v1.0.19) ---
    private static func test11HandleCenterOutAndAspectResizing() {
        let initialRect = CGRect(x: 200, y: 200, width: 200, height: 100)
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let center = CGPoint(x: initialRect.midX, y: initialRect.midY) // (300, 250)

        // 1. Bottom-Right handle dragged with Option key (center-out expansion)
        let brAnchor = SelectionBoxGeometry.anchorPoint(for: .bottomRight, in: initialRect)
        let brTarget = CGPoint(x: 450, y: 150) // dx = 150, dy = 100 from center
        let brResized = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: brTarget,
            anchor: brAnchor,
            bounds: bounds,
            currentRect: initialRect,
            shiftKeyPressed: false,
            optionKeyPressed: true
        )
        TestHarness.assertEqual(brResized.midX, center.x, "Center-out BR resize maintains midX at initial center")
        TestHarness.assertEqual(brResized.midY, center.y, "Center-out BR resize maintains midY at initial center")
        TestHarness.assertEqual(brResized.width, 300.0, "Center-out BR resize doubles dx from center")
        TestHarness.assertEqual(brResized.height, 200.0, "Center-out BR resize doubles dy from center")

        // 2. Bottom-Right handle dragged with Option + Shift (center-out 1:1 aspect lock)
        let brSquare = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: brTarget,
            anchor: brAnchor,
            bounds: bounds,
            currentRect: initialRect,
            shiftKeyPressed: true,
            optionKeyPressed: true
        )
        TestHarness.assertEqual(brSquare.midX, center.x, "Center-out 1:1 square maintains center midX")
        TestHarness.assertEqual(brSquare.midY, center.y, "Center-out 1:1 square maintains center midY")
        TestHarness.assertEqual(brSquare.width, brSquare.height, "Center-out 1:1 square width equals height")

        // 3. Top-Center handle dragged with Option key
        let tcAnchor = SelectionBoxGeometry.anchorPoint(for: .topCenter, in: initialRect)
        let tcTarget = CGPoint(x: 300, y: 350) // dy = 100 from center
        let tcResized = SelectionBoxGeometry.calculateResizedRect(
            handle: .topCenter,
            currentPoint: tcTarget,
            anchor: tcAnchor,
            bounds: bounds,
            currentRect: initialRect,
            shiftKeyPressed: false,
            optionKeyPressed: true
        )
        TestHarness.assertEqual(tcResized.midX, center.x, "Top-center option resize maintains midX")
        TestHarness.assertEqual(tcResized.midY, center.y, "Top-center option resize maintains midY")
        TestHarness.assertEqual(tcResized.width, initialRect.width, "Top-center option resize preserves width")
        TestHarness.assertEqual(tcResized.height, 200.0, "Top-center option resize doubles dy")

        // 4. Middle-Right handle dragged with Option key
        let mrAnchor = SelectionBoxGeometry.anchorPoint(for: .middleRight, in: initialRect)
        let mrTarget = CGPoint(x: 450, y: 250) // dx = 150 from center
        let mrResized = SelectionBoxGeometry.calculateResizedRect(
            handle: .middleRight,
            currentPoint: mrTarget,
            anchor: mrAnchor,
            bounds: bounds,
            currentRect: initialRect,
            shiftKeyPressed: false,
            optionKeyPressed: true
        )
        TestHarness.assertEqual(mrResized.midX, center.x, "Middle-right option resize maintains midX")
        TestHarness.assertEqual(mrResized.midY, center.y, "Middle-right option resize maintains midY")
        TestHarness.assertEqual(mrResized.width, 300.0, "Middle-right option resize doubles dx")
        TestHarness.assertEqual(mrResized.height, initialRect.height, "Middle-right option resize preserves height")
    }
}
