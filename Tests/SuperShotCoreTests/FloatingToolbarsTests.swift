import Foundation
import CoreGraphics
import AppKit
import SuperShotCore
import SuperShot

/// Automated verification suite for Milestone 2:
/// Floating Toolbars, Color Palette Popover, Keyboard Shortcuts, and Reviewer 1 Polish.
public struct FloatingToolbarsTests {

    public static func run() {
        TestHarness.startSuite("Floating Toolbars & Color Palette Tests (M2)")

        testToolMappingAndCounts()
        testEdgeAwareLayoutDefault()
        testEdgeAwareLayoutFlippingRightToLeft()
        testEdgeAwareLayoutFlippingBottomToTop()
        testEdgeAwareLayoutCornerCollision()
        testKeyboardShortcutDispatcher()
        testColorPresetParseRGBGuard()
        testStorageManagerConvenienceOverloads()
        testPalettePresetSelectionAndRecolor()
        testPaletteHexValidation()
        testPalettePresetClamping16()
        testAppSettingsPersistenceAcrossSessions()
        testPresetUpdateAtCapacity16()
        testEndToEndCaptureOverlayAnnotationCompositing()
    }

    // 1. Tool Mapping & Counts
    private static func testToolMappingAndCounts() {
        let tools = AnnotationToolType.allCases
        TestHarness.assertEqual(tools.count, 9, "Should expose exactly 9 annotation tools")
        TestHarness.assertEqual(AnnotationToolType.select.sfSymbol, "cursorarrow", "Select tool sfSymbol is cursorarrow")
        TestHarness.assertEqual(AnnotationToolType.rectangle.sfSymbol, "rectangle", "Rectangle tool sfSymbol is rectangle")
        TestHarness.assertEqual(AnnotationToolType.ellipse.sfSymbol, "circle", "Ellipse tool sfSymbol is circle")
        TestHarness.assertEqual(AnnotationToolType.arrow.sfSymbol, "arrow.up.right", "Arrow tool sfSymbol is arrow.up.right")
        TestHarness.assertEqual(AnnotationToolType.line.sfSymbol, "line.diagonal", "Line tool sfSymbol is line.diagonal")
        TestHarness.assertEqual(AnnotationToolType.pen.sfSymbol, "pencil.tip", "Pen tool sfSymbol is pencil.tip")
        TestHarness.assertEqual(AnnotationToolType.highlighter.sfSymbol, "highlighter", "Highlighter tool sfSymbol is highlighter")
        TestHarness.assertEqual(AnnotationToolType.text.sfSymbol, "textformat", "Text tool sfSymbol is textformat")
        TestHarness.assertEqual(AnnotationToolType.blur.sfSymbol, "checkerboard.rectangle", "Blur tool sfSymbol is checkerboard.rectangle")
    }

    // 2. Edge-Aware Layout: Centered Box
    private static func testEdgeAwareLayoutDefault() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 500, y: 300, width: 400, height: 300)

        let (vFrame, hFrame) = ToolbarLayoutCalculator.computeLayout(
            selectionRect: selection,
            screenRect: screen
        )

        TestHarness.assertTrue(vFrame.minX >= selection.maxX, "Vertical toolbar should anchor to right")
        TestHarness.assertEqual(vFrame.minY, selection.minY, "Vertical toolbar should align with selection top")
        TestHarness.assertTrue(hFrame.minY >= selection.maxY, "Horizontal toolbar should anchor below selection")
        TestHarness.assertTrue(hFrame.maxX <= screen.maxX, "Horizontal toolbar must stay within screen bounds")
    }

    // 3. Edge-Aware Layout: Right Screen Edge Flip
    private static func testEdgeAwareLayoutFlippingRightToLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 1800, y: 200, width: 110, height: 400)

        let (vFrame, _) = ToolbarLayoutCalculator.computeLayout(
            selectionRect: selection,
            screenRect: screen
        )

        TestHarness.assertTrue(vFrame.maxX <= selection.minX, "Vertical toolbar must flip to left of selection")
        TestHarness.assertTrue(vFrame.minX >= screen.minX, "Vertical toolbar must remain on screen")
    }

    // 4. Edge-Aware Layout: Bottom Screen Edge Flip
    private static func testEdgeAwareLayoutFlippingBottomToTop() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 400, y: 1000, width: 500, height: 75)

        let (_, hFrame) = ToolbarLayoutCalculator.computeLayout(
            selectionRect: selection,
            screenRect: screen
        )

        TestHarness.assertTrue(hFrame.maxY <= selection.minY, "Horizontal toolbar must flip above selection")
        TestHarness.assertTrue(hFrame.minY >= screen.minY, "Horizontal toolbar must remain on screen")
    }

    // 5. Edge-Aware Layout: Corner Clamping & Collision
    private static func testEdgeAwareLayoutCornerCollision() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 1850, y: 1020, width: 60, height: 50)

        let (vFrame, hFrame) = ToolbarLayoutCalculator.computeLayout(
            selectionRect: selection,
            screenRect: screen
        )

        TestHarness.assertFalse(vFrame.intersects(hFrame), "Vertical and horizontal toolbars must not collide")
        TestHarness.assertTrue(screen.contains(vFrame), "Vertical toolbar must stay completely on screen")
        TestHarness.assertTrue(screen.contains(hFrame), "Horizontal toolbar must stay completely on screen")
    }

    // 6. Keyboard Shortcut Dispatcher
    private static func testKeyboardShortcutDispatcher() {
        let vm = FloatingToolbarsViewModel()
        var copyCalled = false
        var saveCalled = false
        var cancelCalled = false

        vm.onCopyRequested = { copyCalled = true }
        vm.onSaveRequested = { saveCalled = true }
        vm.onCancelRequested = { cancelCalled = true }

        let eventTool4 = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "4",
            charactersIgnoringModifiers: "4",
            isARepeat: false,
            keyCode: 21
        )!
        let handledTool4 = ToolbarKeyShortcutHandler.handleKeyEvent(event: eventTool4, viewModel: vm)
        TestHarness.assertTrue(handledTool4, "Shortcut 4 should be handled")
        TestHarness.assertEqual(vm.activeTool, .arrow, "Key 4 must select Arrow tool")

        let eventReturn = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        let handledReturn = ToolbarKeyShortcutHandler.handleKeyEvent(event: eventReturn, viewModel: vm)
        TestHarness.assertTrue(handledReturn, "Return key should be handled")
        TestHarness.assertTrue(copyCalled, "Return key must trigger onCopyRequested")

        let eventEsc = NSEvent.keyEvent(
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
        let handledEsc = ToolbarKeyShortcutHandler.handleKeyEvent(event: eventEsc, viewModel: vm)
        TestHarness.assertTrue(handledEsc, "Escape key should be handled")
        TestHarness.assertTrue(cancelCalled, "Escape key must trigger onCancelRequested")

        let eventCmdS = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: 1
        )!
        let handledCmdS = ToolbarKeyShortcutHandler.handleKeyEvent(event: eventCmdS, viewModel: vm)
        TestHarness.assertTrue(handledCmdS, "Cmd+S should be handled")
        TestHarness.assertTrue(saveCalled, "Cmd+S must trigger onSaveRequested")
    }

    // 7. Reviewer 1 Polish: ColorPreset.parseRGB Guard
    private static func testColorPresetParseRGBGuard() {
        TestHarness.assertNil(ColorPreset.parseRGB(hex: "invalid_color"), "Invalid hex string must return nil")
        TestHarness.assertNil(ColorPreset.parseRGB(hex: ""), "Empty string must return nil")
        TestHarness.assertNil(ColorPreset.parseRGB(hex: "#GGGGGG"), "Non-hex characters must return nil")
        TestHarness.assertNil(ColorPreset.parseRGB(hex: "#12"), "Short hex must return nil")

        let valid = ColorPreset.parseRGB(hex: "#00FF00")
        TestHarness.assertTrue(valid != nil, "Valid hex #00FF00 must parse successfully")
        if let rgb = valid {
            TestHarness.assertTrue(abs(rgb.r - 0.0) < 1e-4, "Red component should be 0.0")
            TestHarness.assertTrue(abs(rgb.g - 1.0) < 1e-4, "Green component should be 1.0")
            TestHarness.assertTrue(abs(rgb.b - 0.0) < 1e-4, "Blue component should be 0.0")
        }
    }

    // 8. Reviewer 1 Polish: StorageManager Convenience Overloads
    private static func testStorageManagerConvenienceOverloads() {
        let sandbox = TestHarness.createSandbox(prefix: "StorageConvenience")
        defer { TestHarness.cleanupSandbox(sandbox) }

        let storage = StorageManager(baseDirectory: sandbox)
        let sampleImage = makeTestCGImage(width: 100, height: 100)

        guard let savedItem = try? storage.save(image: sampleImage) else {
            TestHarness.recordFail("Storage Convenience", reason: "Failed to save image in storage")
            return
        }

        let loaded = storage.load(id: savedItem.id)
        TestHarness.assertNotNil(loaded, "load(id:) must retrieve saved CGImage")
        if let img = loaded {
            TestHarness.assertEqual(img.width, 100, "Loaded image width must match")
            TestHarness.assertEqual(img.height, 100, "Loaded image height must match")
        }

        do {
            try storage.delete(id: savedItem.id)
            let loadedAfterDelete = storage.load(id: savedItem.id)
            TestHarness.assertNil(loadedAfterDelete, "load(id:) after delete(id:) must return nil")
        } catch {
            TestHarness.recordFail("Storage Convenience Delete", reason: "delete(id:) should not throw error: \(error)")
        }
    }

    // 9. Palette Preset Selection & Recoloring
    private static func testPalettePresetSelectionAndRecolor() {
        let appSettings = AppSettings()
        let bluePreset = ColorPreset(name: "Test Blue", hex: "#007AFF")
        appSettings.activeColorHex = bluePreset.hex
        TestHarness.assertEqual(appSettings.activeColorHex, "#007AFF", "Selecting preset updates activeColorHex")
    }

    // 10. Palette HEX Validation
    private static func testPaletteHexValidation() {
        TestHarness.assertTrue(ColorPreset.isValid(hex: "#FF0000"), "#FF0000 is valid")
        TestHarness.assertTrue(ColorPreset.isValid(hex: "00FF00"), "00FF00 without hash is valid")
        TestHarness.assertTrue(ColorPreset.isValid(hex: "#FFF"), "#FFF 3-char is valid")
        TestHarness.assertFalse(ColorPreset.isValid(hex: "hello"), "hello is invalid")
        TestHarness.assertFalse(ColorPreset.isValid(hex: "#12345"), "5-char hex is invalid")
    }

    // 11. Palette Preset Clamping to 16
    private static func testPalettePresetClamping16() {
        let appSettings = AppSettings()
        appSettings.resetPresets()
        TestHarness.assertEqual(appSettings.presets.count, 8, "Initial defaults count must be 8")

        for i in 1...8 {
            let p = ColorPreset(name: "Extra \(i)", hex: String(format: "#%06X", i * 0x101010))
            let added = appSettings.addPreset(p)
            TestHarness.assertTrue(added, "Should successfully add up to 16 presets")
        }
        TestHarness.assertEqual(appSettings.presets.count, 16, "Must have exactly 16 presets")

        let p17 = ColorPreset(name: "Overflow", hex: "#FFFFFF")
        let added17 = appSettings.addPreset(p17)
        TestHarness.assertFalse(added17, "17th preset addition must be rejected")
        TestHarness.assertEqual(appSettings.presets.count, 16, "Count must remain clamped at 16")

        // In-place update of existing preset at capacity 16 must succeed
        let existingHex = appSettings.presets[0].hex
        let updateSuccess = appSettings.addPreset(ColorPreset(name: "Renamed In Clamping Test", hex: existingHex))
        TestHarness.assertTrue(updateSuccess, "addPreset must update existing preset at capacity 16")
        TestHarness.assertEqual(appSettings.presets.count, 16, "Preset count remains 16 after in-place update")
        TestHarness.assertEqual(appSettings.presets[0].name, "Renamed In Clamping Test", "Preset name updated to new name")
    }

    // 12. AppSettings Persistence Across Sessions
    private static func testAppSettingsPersistenceAcrossSessions() {
        let sandbox = TestHarness.createSandbox(prefix: "AppSettingsPersistence")
        defer { TestHarness.cleanupSandbox(sandbox) }

        let settingsURL = sandbox.appendingPathComponent("settings.json")
        let settingsA = AppSettings(settingsURL: settingsURL)
        settingsA.activeColorHex = "#34C759"
        settingsA.activeStrokeWidth = 8.0
        settingsA.activeFontSize = 36.0

        let snapshot = settingsA.makeSnapshot()
        guard let data = try? JSONEncoder().encode(snapshot),
              (try? data.write(to: settingsURL, options: .atomic)) != nil else {
            TestHarness.recordFail("AppSettings Persistence", reason: "Failed to write snapshot to disk")
            return
        }

        let settingsB = AppSettings(settingsURL: settingsURL)
        TestHarness.assertEqual(settingsB.activeColorHex, "#34C759", "Active color must persist")
        TestHarness.assertEqual(settingsB.activeStrokeWidth, 8.0, "Active stroke width must persist")
        TestHarness.assertEqual(settingsB.activeFontSize, 36.0, "Active font size must persist")
    }

    // 13. Regression Test: Update Existing Preset at Capacity 16 vs 17th Unique
    private static func testPresetUpdateAtCapacity16() {
        let appSettings = AppSettings()
        appSettings.resetPresets()
        TestHarness.assertEqual(appSettings.presets.count, 8, "Initial presets count is 8")

        for i in 1...8 {
            let p = ColorPreset(name: "Extra \(i)", hex: String(format: "#%06X", i * 0x111111))
            let added = appSettings.addPreset(p)
            TestHarness.assertTrue(added, "Successfully added preset up to capacity 16")
        }
        TestHarness.assertEqual(appSettings.presets.count, 16, "Presets count must be exactly 16")

        // Update existing preset's name at capacity 16
        let existingHex = appSettings.presets[0].hex
        let updateSuccess = appSettings.addPreset(ColorPreset(name: "Renamed At Capacity", hex: existingHex))
        TestHarness.assertTrue(updateSuccess, "addPreset must return true when updating existing preset name at capacity 16")
        TestHarness.assertEqual(appSettings.presets.count, 16, "Preset count remains 16 after update")
        TestHarness.assertEqual(appSettings.presets[0].name, "Renamed At Capacity", "Preset name updated to new name")

        // Attempting to add a 17th unique preset returns false
        let unique17 = ColorPreset(name: "Unique 17", hex: "#ABCDEF")
        let add17Success = appSettings.addPreset(unique17)
        TestHarness.assertFalse(add17Success, "addPreset must return false for 17th unique preset at capacity 16")
        TestHarness.assertEqual(appSettings.presets.count, 16, "Preset count remains 16 after rejected addition")
        TestHarness.assertFalse(appSettings.presets.contains(where: { $0.hex == "#ABCDEF" }), "17th unique preset not present")
    }

    // 14. End-to-End CaptureOverlayWindow + FloatingToolbars + AnnotationEngine + ImageRenderer Integration
    private static func testEndToEndCaptureOverlayAnnotationCompositing() {
        let mockProvider = MockScreenCaptureProvider()
        let manager = ScreenCaptureManager(provider: mockProvider)
        guard let captured = manager.captureMainScreen() else {
            TestHarness.recordFail("Overlay E2E", reason: "Failed to capture mock main screen")
            return
        }

        let settings = AppSettings()
        let overlayWindow = CaptureOverlayWindow(capturedScreen: captured, appSettings: settings)
        guard let contentView = overlayWindow.contentViewRef else {
            TestHarness.recordFail("Overlay E2E", reason: "contentViewRef is nil")
            return
        }

        // Establish 300x200 selection region
        contentView.selectionRect = CGRect(x: 200, y: 200, width: 300, height: 200)
        TestHarness.assertEqual(contentView.toolbarsViewModel.selectionRect, CGRect(x: 200, y: 200, width: 300, height: 200), "Toolbars viewModel synchronized with selectionRect")

        // Select Rectangle tool via FloatingToolbarsViewModel
        contentView.toolbarsViewModel.selectTool(.rectangle)
        TestHarness.assertEqual(contentView.annotationEngine.activeTool, .rectangle, "Selecting tool on toolbar updates overlay AnnotationEngine.activeTool")

        // Draw rectangle inside selection
        contentView.annotationEngine.startDrag(at: CGPoint(x: 220, y: 230), colorHex: "#FF3B30", strokeWidth: 4.0)
        contentView.annotationEngine.updateDrag(to: CGPoint(x: 320, y: 310))
        let drawnObj = contentView.annotationEngine.endDrag(at: CGPoint(x: 320, y: 310))
        TestHarness.assertNotNil(drawnObj, "Drew rectangle annotation inside overlay")
        TestHarness.assertTrue(contentView.toolbarsViewModel.canUndo, "Toolbar canUndo updated to true after drawing")

        // Recolor selected object via toolbar color selection callback
        contentView.toolbarsViewModel.selectColor("#007AFF")
        TestHarness.assertEqual(contentView.annotationEngine.selectedObject?.colorHex, "#007AFF", "Toolbar color selection recolors selected annotation object in-place")

        // Render final composited selection image at 2x Retina (300x200 pt -> 600x400 px)
        let composited = contentView.renderFinalSelectionImage()
        TestHarness.assertNotNil(composited, "Overlay renderFinalSelectionImage produced composited CGImage")
        TestHarness.assertEqual(composited?.width, 600, "Composited Retina @2x width is 600px")
        TestHarness.assertEqual(composited?.height, 400, "Composited Retina @2x height is 400px")
    }

    // Helper: Synthetic CGImage Creator
    private static func makeTestCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
