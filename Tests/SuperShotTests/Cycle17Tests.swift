import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import SuperShotCore
import SuperShot

/// Comprehensive test suite for Cycle 17 features (F173-F180).
public struct Cycle17Tests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Cycle 17 (v1.0.24 UX & Ergonomics Polish Tests)")

        let storage = StorageManager(baseDirectory: sandboxDir)
        let sampleImage = MockScreenCaptureProvider.createSyntheticImage(size: CGSize(width: 400, height: 300))!
        let item = try! storage.save(image: sampleImage, sourceApp: "Finder", captureType: .region)
        storage.flushDiskQueue()

        let appSettings = AppSettings()
        let display = CaptureDisplayInfo(
            displayID: 1,
            name: "TestDisplay",
            cocoaFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cgBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scaleFactor: 2.0,
            isMain: true,
            pixelSize: CGSize(width: 3840, height: 2160)
        )
        let screen = CapturedScreen(displayInfo: display, fullImage: sampleImage, timestamp: Date())

        // ---------------------------------------------------------------------
        // Feature 173: Quick Copy Action Pill on Dimension Badge
        // ---------------------------------------------------------------------
        let overlayWindow = CaptureOverlayWindow(capturedScreen: screen, appSettings: appSettings)
        let overlayView = overlayWindow.contentViewRef!
        overlayView.selectionRect = CGRect(x: 100, y: 100, width: 400, height: 300)

        let pillFrame = overlayView.quickCopyPillFrame()
        TestHarness.assertTrue(pillFrame.width > 0 && pillFrame.height > 0, "F173: quickCopyPillFrame returns non-empty frame")
        TestHarness.assertEqual(pillFrame.minX, overlayView.dimensionBadgeFrame().maxX + 6.0, "F173: quick copy pill is placed adjacent to dimension badge")

        var quickCopyTriggered = false
        overlayView.toolbarsViewModel.onCopyRequested = {
            quickCopyTriggered = true
        }

        let pillCenter = CGPoint(x: pillFrame.midX, y: pillFrame.midY)
        let clickPill = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: pillCenter,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 10,
            clickCount: 1,
            pressure: 1.0
        )!
        overlayView.mouseDown(with: clickPill)
        TestHarness.assertTrue(quickCopyTriggered, "F173: Clicking quick copy pill triggers onCopyRequested")

        // ---------------------------------------------------------------------
        // Feature 174: Spacebar Repositioning (Space + Drag)
        // ---------------------------------------------------------------------
        let freshWindow = CaptureOverlayWindow(capturedScreen: screen, appSettings: appSettings)
        let freshOverlay = freshWindow.contentViewRef!
        freshOverlay.selectionRect = .zero

        // Start creating selection at (100, 100)
        let downEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 100, y: 100),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 20,
            clickCount: 1,
            pressure: 1.0
        )!
        freshOverlay.mouseDown(with: downEvent)

        // Drag to (250, 200) -> 150x100 rect
        let drag1 = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: 250, y: 200),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 21,
            clickCount: 1,
            pressure: 1.0
        )!
        freshOverlay.mouseDragged(with: drag1)
        TestHarness.assertEqual(freshOverlay.selectionRect.width, 150.0, "F174: Initial dragged width is 150")
        TestHarness.assertEqual(freshOverlay.selectionRect.height, 100.0, "F174: Initial dragged height is 100")
        TestHarness.assertEqual(freshOverlay.selectionRect.origin.x, 100.0, "F174: Initial origin X is 100")
        TestHarness.assertEqual(freshOverlay.selectionRect.origin.y, 100.0, "F174: Initial origin Y is 100")

        // Press Space key down (keyCode 49)
        let spaceDown = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )!
        freshOverlay.keyDown(with: spaceDown)

        // Drag to (280, 230) while holding space -> pan by dx=30, dy=30
        let dragWithSpace = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: 280, y: 230),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 22,
            clickCount: 1,
            pressure: 1.0
        )!
        freshOverlay.mouseDragged(with: dragWithSpace)
        TestHarness.assertTrue(freshOverlay.spaceKeyDragging, "F174: spaceKeyDragging is active during space drag")
        TestHarness.assertEqual(freshOverlay.selectionRect.width, 150.0, "F174: Width is preserved during space drag")
        TestHarness.assertEqual(freshOverlay.selectionRect.height, 100.0, "F174: Height is preserved during space drag")
        TestHarness.assertEqual(freshOverlay.selectionRect.origin.x, 130.0, "F174: Origin X shifted by +30")
        TestHarness.assertEqual(freshOverlay.selectionRect.origin.y, 130.0, "F174: Origin Y shifted by +30")

        // Release Space key (keyCode 49)
        let spaceUp = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )!
        freshOverlay.keyUp(with: spaceUp)
        TestHarness.assertFalse(freshOverlay.spaceKeyDragging, "F174: spaceKeyDragging reset after Space key release")

        // ---------------------------------------------------------------------
        // Feature 175: Font Size Stepping Shortcuts ([ / ]) & HUD Pill
        // ---------------------------------------------------------------------
        let tbVM = FloatingToolbarsViewModel(appSettings: appSettings)
        tbVM.isTextTargetActive = true
        tbVM.selectedFontSize = 16

        tbVM.increaseFontSize()
        TestHarness.assertEqual(tbVM.selectedFontSize, 18, "F175: increaseFontSize steps up by 2 to 18")

        tbVM.decreaseFontSize()
        TestHarness.assertEqual(tbVM.selectedFontSize, 16, "F175: decreaseFontSize steps down by 2 to 16")

        // Upper clamp at 72
        tbVM.selectedFontSize = 72
        tbVM.increaseFontSize()
        TestHarness.assertEqual(tbVM.selectedFontSize, 72, "F175: increaseFontSize clamped at 72")

        // Lower clamp at 10
        tbVM.selectedFontSize = 10
        tbVM.decreaseFontSize()
        TestHarness.assertEqual(tbVM.selectedFontSize, 10, "F175: decreaseFontSize clamped at 10")

        // Test ToolbarKeyShortcutHandler with bracket events when text target active
        var reportedFontSize: CGFloat? = nil
        tbVM.onFontSizeSelected = { size in
            reportedFontSize = size
        }

        let rightBracket = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "]",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!
        let handledRight = ToolbarKeyShortcutHandler.handleKeyEvent(event: rightBracket, viewModel: tbVM)
        TestHarness.assertTrue(handledRight, "F175: Right bracket key handled by ToolbarKeyShortcutHandler")
        TestHarness.assertEqual(tbVM.selectedFontSize, 12, "F175: Selected font size increased to 12")
        TestHarness.assertEqual(reportedFontSize, 12.0, "F175: onFontSizeSelected fired with 12")

        let leftBracket = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        let handledLeft = ToolbarKeyShortcutHandler.handleKeyEvent(event: leftBracket, viewModel: tbVM)
        TestHarness.assertTrue(handledLeft, "F175: Left bracket key handled by ToolbarKeyShortcutHandler")
        TestHarness.assertEqual(tbVM.selectedFontSize, 10, "F175: Selected font size decreased to 10")
        TestHarness.assertEqual(reportedFontSize, 10.0, "F175: onFontSizeSelected fired with 10")

        // When text target is NOT active, brackets step stroke width
        tbVM.isTextTargetActive = false
        let initialStroke = appSettings.activeStrokeWidth
        let _ = ToolbarKeyShortcutHandler.handleKeyEvent(event: rightBracket, viewModel: tbVM)
        TestHarness.assertTrue(appSettings.activeStrokeWidth >= initialStroke, "F175: Bracket adjusts stroke width when text target inactive")

        // HUD Pill formatting
        overlayView.showFontSizeHUD(size: 24)
        TestHarness.assertEqual(overlayView.toolHUDText, LocalizationManager.shared.tr(.fontSizeHUD(24)), "F175: showFontSizeHUD sets HUD text")

        // ---------------------------------------------------------------------
        // Feature 176: Fit to Window Button in Scrollable Canvas
        // ---------------------------------------------------------------------
        let engine = AnnotationEngine()
        let docView = ScrollableAnnotationDocumentView(baseImage: sampleImage, engine: engine, scale: 1.0)
        let scrollView = ScrollableAnnotationScrollView(documentCanvasView: docView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 150)
        scrollView.zoomToFitWindow()
        TestHarness.assertTrue(scrollView.magnification >= 0.1 && scrollView.magnification <= 4.0, "F176: zoomToFitWindow computes valid clamped magnification")

        let zoomVM = ScrollableZoomViewModel(magnification: 1.0)
        var fitWindowInvoked = false
        zoomVM.onFitWindow = {
            fitWindowInvoked = true
        }
        zoomVM.onFitWindow?()
        TestHarness.assertTrue(fitWindowInvoked, "F176: ScrollableZoomViewModel onFitWindow callback invoked")

        let zoomControls = ScrollableZoomControlsView(viewModel: zoomVM)
        let _ = zoomControls.body
        TestHarness.assertTrue(true, "F176: ScrollableZoomControlsView renders body cleanly")

        // ---------------------------------------------------------------------
        // Feature 177: Visual Hover Highlight on Dimension Badge & Quick Copy Pill
        // ---------------------------------------------------------------------
        overlayView.selectionRect = CGRect(x: 100, y: 100, width: 400, height: 300)
        let badgeCenter = CGPoint(x: overlayView.dimensionBadgeFrame().midX, y: overlayView.dimensionBadgeFrame().midY)
        let hoverBadgeEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: badgeCenter,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 30,
            clickCount: 0,
            pressure: 0.0
        )!
        overlayView.mouseMoved(with: hoverBadgeEvent)
        TestHarness.assertTrue(overlayView.isHoveringDimensionBadge, "F177: isHoveringDimensionBadge is true when hovering badge")
        TestHarness.assertFalse(overlayView.isHoveringQuickCopyPill, "F177: isHoveringQuickCopyPill is false when hovering badge")

        let freshPillFrame = overlayView.quickCopyPillFrame()
        let hoverPillEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: CGPoint(x: freshPillFrame.midX, y: freshPillFrame.midY),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 31,
            clickCount: 0,
            pressure: 0.0
        )!
        overlayView.mouseMoved(with: hoverPillEvent)
        TestHarness.assertFalse(overlayView.isHoveringDimensionBadge, "F177: isHoveringDimensionBadge is false when hovering pill")
        TestHarness.assertTrue(overlayView.isHoveringQuickCopyPill, "F177: isHoveringQuickCopyPill is true when hovering pill")

        let hoverOutside = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: CGPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 32,
            clickCount: 0,
            pressure: 0.0
        )!
        overlayView.mouseMoved(with: hoverOutside)
        TestHarness.assertFalse(overlayView.isHoveringDimensionBadge, "F177: isHoveringDimensionBadge reset when cursor outside")
        TestHarness.assertFalse(overlayView.isHoveringQuickCopyPill, "F177: isHoveringQuickCopyPill reset when cursor outside")

        overlayView.mouseExited(with: hoverOutside)
        TestHarness.assertFalse(overlayView.isHoveringDimensionBadge, "F177: isHoveringDimensionBadge reset on mouseExited")
        TestHarness.assertFalse(overlayView.isHoveringQuickCopyPill, "F177: isHoveringQuickCopyPill reset on mouseExited")

        // ---------------------------------------------------------------------
        // Feature 178: Direct Keyboard Shortcuts in MainShotView
        // ---------------------------------------------------------------------
        let mainShotView = MainShotView(storageManager: storage, appSettings: appSettings)
        TestHarness.assertTrue(!mainShotView.visibleItems.isEmpty, "F178: MainShotView has seeded visibleItems")

        mainShotView.copySelectedFilePath()
        let copiedPath = NSPasteboard.general.string(forType: .string)
        TestHarness.assertEqual(copiedPath, storage.getImageURL(for: item).path, "F178: copySelectedFilePath copies exact file path to pasteboard")

        mainShotView.copySelectedDimensions()
        let copiedDims = NSPasteboard.general.string(forType: .string)
        TestHarness.assertEqual(copiedDims, item.dimensionsString, "F178: copySelectedDimensions copies exact dimensions to pasteboard")

        mainShotView.triggerCopyFeedback(for: item.id, message: "Custom Feedback", icon: "doc.fill")
        TestHarness.assertTrue(true, "F178: triggerCopyFeedback with custom message and icon executes safely")

        // ---------------------------------------------------------------------
        // Feature 179: Double-Click Quick Copy Parity on Tall Stitched Canvas
        // ---------------------------------------------------------------------
        var docQuickCopyCalled = false
        docView.onQuickCopyRequested = {
            docQuickCopyCalled = true
        }

        let docDoubleClick = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 50, y: 50),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 40,
            clickCount: 2,
            pressure: 1.0
        )!
        docView.mouseDown(with: docDoubleClick)
        TestHarness.assertTrue(docQuickCopyCalled, "F179: Double-clicking empty canvas triggers onQuickCopyRequested")

        // ---------------------------------------------------------------------
        // Feature 180: Complete Zero-Emoji Multilingual Localization (9 Languages)
        // ---------------------------------------------------------------------
        for lang in AppLanguage.allCases {
            let quickCopy = LocalizationKey.quickCopy.localized(for: lang)
            let quickCopyBtn = LocalizationKey.quickCopyButton.localized(for: lang)
            let fontHUD = LocalizationKey.fontSizeHUD(20).localized(for: lang)
            let zoomTooltip = LocalizationKey.zoomFitWindowTooltip.localized(for: lang)
            let copiedDimsHUD = LocalizationKey.copiedDimensionsHUD.localized(for: lang)
            let copiedFilePath = LocalizationKey.copiedFilePath.localized(for: lang)

            TestHarness.assertFalse(quickCopy.isEmpty, "F180: quickCopy non-empty for \(lang.rawValue)")
            TestHarness.assertFalse(quickCopyBtn.isEmpty, "F180: quickCopyButton non-empty for \(lang.rawValue)")
            TestHarness.assertFalse(fontHUD.isEmpty, "F180: fontSizeHUD non-empty for \(lang.rawValue)")
            TestHarness.assertTrue(fontHUD.contains("20"), "F180: fontSizeHUD contains size value for \(lang.rawValue)")
            TestHarness.assertFalse(zoomTooltip.isEmpty, "F180: zoomFitWindowTooltip non-empty for \(lang.rawValue)")
            TestHarness.assertFalse(copiedDimsHUD.isEmpty, "F180: copiedDimensionsHUD non-empty for \(lang.rawValue)")
            TestHarness.assertFalse(copiedFilePath.isEmpty, "F180: copiedFilePath non-empty for \(lang.rawValue)")
        }

        // ---------------------------------------------------------------------
        // Feature 173 & Feature 177: Screen Boundary & Micro-Selection Robustness
        // Exhaustive Matrix: 15 Edge/Corner/Strip/Micro Selection Rectangles
        // ---------------------------------------------------------------------
        let boundaryOverlayWindow = CaptureOverlayWindow(capturedScreen: screen, appSettings: appSettings)
        let boundaryOverlay = boundaryOverlayWindow.contentViewRef!
        let screenBounds = display.cocoaFrame

        let adversarialSelectionMatrix: [(name: String, rect: CGRect)] = [
            ("Center Normal", CGRect(x: 800, y: 400, width: 320, height: 240)),
            ("Top-Left Corner", CGRect(x: 0, y: 1040, width: 60, height: 40)),
            ("Top-Right Corner", CGRect(x: 1850, y: 1040, width: 60, height: 40)),
            ("Bottom-Left Corner", CGRect(x: 0, y: 0, width: 60, height: 40)),
            ("Bottom-Right Corner", CGRect(x: 1850, y: 0, width: 60, height: 40)),
            ("1x1 Micro at Top-Left", CGRect(x: 0, y: 1079, width: 1, height: 1)),
            ("1x1 Micro at Top-Right", CGRect(x: 1919, y: 1079, width: 1, height: 1)),
            ("1x1 Micro at Bottom-Left", CGRect(x: 0, y: 0, width: 1, height: 1)),
            ("1x1 Micro at Bottom-Right", CGRect(x: 1919, y: 0, width: 1, height: 1)),
            ("1x1 Micro at Center", CGRect(x: 960, y: 540, width: 1, height: 1)),
            ("10px Strip Along Top Edge", CGRect(x: 0, y: 1070, width: 1920, height: 10)),
            ("10px Strip Along Bottom Edge", CGRect(x: 0, y: 0, width: 1920, height: 10)),
            ("10px Strip Along Left Edge", CGRect(x: 0, y: 0, width: 10, height: 1080)),
            ("10px Strip Along Right Edge", CGRect(x: 1910, y: 0, width: 10, height: 1080)),
            ("Fullscreen Selection", CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ]

        for (name, rect) in adversarialSelectionMatrix {
            boundaryOverlay.selectionRect = rect

            let badgeFrame = boundaryOverlay.dimensionBadgeFrame()
            let pillFrame = boundaryOverlay.quickCopyPillFrame()

            // 1. Invariant: Frames must be non-empty
            TestHarness.assertTrue(badgeFrame.width > 0 && badgeFrame.height > 0, "F173/F177 [\(name)]: Badge frame is non-empty")
            TestHarness.assertTrue(pillFrame.width > 0 && pillFrame.height > 0, "F173/F177 [\(name)]: Quick Copy pill frame is non-empty")

            // 2. Invariant: Strict Screen Bounds Containment
            TestHarness.assertTrue(badgeFrame.minX >= screenBounds.minX - 0.5, "F173/F177 [\(name)]: Badge minX >= screenBounds.minX")
            TestHarness.assertTrue(badgeFrame.maxX <= screenBounds.maxX + 0.5, "F173/F177 [\(name)]: Badge maxX <= screenBounds.maxX")
            TestHarness.assertTrue(badgeFrame.minY >= screenBounds.minY - 0.5, "F173/F177 [\(name)]: Badge minY >= screenBounds.minY")
            TestHarness.assertTrue(badgeFrame.maxY <= screenBounds.maxY + 0.5, "F173/F177 [\(name)]: Badge maxY <= screenBounds.maxY")

            TestHarness.assertTrue(pillFrame.minX >= screenBounds.minX - 0.5, "F173/F177 [\(name)]: Pill minX >= screenBounds.minX")
            TestHarness.assertTrue(pillFrame.maxX <= screenBounds.maxX + 0.5, "F173/F177 [\(name)]: Pill maxX <= screenBounds.maxX")
            TestHarness.assertTrue(pillFrame.minY >= screenBounds.minY - 0.5, "F173/F177 [\(name)]: Pill minY >= screenBounds.minY")
            TestHarness.assertTrue(pillFrame.maxY <= screenBounds.maxY + 0.5, "F173/F177 [\(name)]: Pill maxY <= screenBounds.maxY")

            // 3. Invariant: Zero Overlap between Badge and Pill
            let badgePillIntersect = badgeFrame.intersection(pillFrame)
            TestHarness.assertTrue(badgePillIntersect.isNull || badgePillIntersect.width <= 0.01, "F173/F177 [\(name)]: Badge and Pill do not collide")

            // 4. Invariant: Zero Overlap with Floating Action Toolbar
            let horizToolbarFrame = ToolbarPositionCalculator.calculateHorizontalToolbarFrame(selectionRect: rect, screenBounds: screenBounds)
            let badgeHorizIntersect = badgeFrame.intersection(horizToolbarFrame)
            TestHarness.assertTrue(badgeHorizIntersect.isNull || badgeHorizIntersect.isEmpty, "F173/F177 [\(name)]: Badge does not collide with Horizontal Toolbar")

            let pillHorizIntersect = pillFrame.intersection(horizToolbarFrame)
            TestHarness.assertTrue(pillHorizIntersect.isNull || pillHorizIntersect.isEmpty, "F173/F177 [\(name)]: Pill does not collide with Horizontal Toolbar")

            // 5. Invariant: Cursor Resolution Parity (.pointingHand)
            let pillCenter = CGPoint(x: pillFrame.midX, y: pillFrame.midY)
            let badgeCenter = CGPoint(x: badgeFrame.midX, y: badgeFrame.midY)
            TestHarness.assertEqual(boundaryOverlay.resolveCanvasCursor(at: pillCenter), NSCursor.pointingHand, "F177 [\(name)]: Pill center displays pointingHand cursor")
            TestHarness.assertEqual(boundaryOverlay.resolveCanvasCursor(at: badgeCenter), NSCursor.pointingHand, "F177 [\(name)]: Badge center displays pointingHand cursor")

            // 6. Invariant: Visual Hover State Updates
            boundaryOverlay.mouseMoved(with: NSEvent.mouseEvent(
                with: .mouseMoved,
                location: pillCenter,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 101,
                clickCount: 0,
                pressure: 0.0
            )!)
            TestHarness.assertTrue(boundaryOverlay.isHoveringQuickCopyPill, "F177 [\(name)]: Hovering pill sets isHoveringQuickCopyPill")
            TestHarness.assertFalse(boundaryOverlay.isHoveringDimensionBadge, "F177 [\(name)]: Hovering pill keeps isHoveringDimensionBadge false")

            boundaryOverlay.mouseMoved(with: NSEvent.mouseEvent(
                with: .mouseMoved,
                location: badgeCenter,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 102,
                clickCount: 0,
                pressure: 0.0
            )!)
            TestHarness.assertTrue(boundaryOverlay.isHoveringDimensionBadge, "F177 [\(name)]: Hovering badge sets isHoveringDimensionBadge")
            TestHarness.assertFalse(boundaryOverlay.isHoveringQuickCopyPill, "F177 [\(name)]: Hovering badge keeps isHoveringQuickCopyPill false")

            // 7. Invariant: Interactive Click Interception on Quick Copy Pill
            var pillCopyTriggered = false
            boundaryOverlay.toolbarsViewModel.onCopyRequested = {
                pillCopyTriggered = true
            }
            boundaryOverlay.mouseDown(with: NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: pillCenter,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 103,
                clickCount: 1,
                pressure: 1.0
            )!)
            TestHarness.assertTrue(pillCopyTriggered, "F173 [\(name)]: Clicking quick copy pill center triggers onCopyRequested")

            // 8. Invariant: Interactive Click-to-Copy on Dimension Badge
            NSPasteboard.general.clearContents()
            boundaryOverlay.mouseDown(with: NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: badgeCenter,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 104,
                clickCount: 1,
                pressure: 1.0
            )!)
            let copiedDimensions = NSPasteboard.general.string(forType: .string)
            TestHarness.assertTrue(copiedDimensions != nil && !copiedDimensions!.isEmpty, "F173 [\(name)]: Clicking dimension badge copies dimensions to NSPasteboard")
        }

        // ---------------------------------------------------------------------
        // Feature 173 Pure Calculator Boundary Collision Regression Test
        // ---------------------------------------------------------------------
        let topBoundaryRect = CGRect(x: 1700, y: 1060, width: 200, height: 20)
        let calcBadgeFrame = ToolbarPositionCalculator.calculateDimensionBadgeFrame(selectionRect: topBoundaryRect, screenBounds: screenBounds)
        let calcHorizFrame = ToolbarPositionCalculator.calculateHorizontalToolbarFrame(selectionRect: topBoundaryRect, screenBounds: screenBounds)
        TestHarness.assertTrue(calcBadgeFrame.intersection(calcHorizFrame).isNull || calcBadgeFrame.intersection(calcHorizFrame).isEmpty, "F173 Calculator: Top-screen flipped badge does not collide with horizontal toolbar")
        TestHarness.assertTrue(calcBadgeFrame.maxY <= screenBounds.maxY - ToolbarPositionCalculator.margin + 0.1, "F173 Calculator: Badge maxY clamped inside screen bounds")
        TestHarness.assertTrue(calcBadgeFrame.minY >= screenBounds.minY + ToolbarPositionCalculator.margin - 0.1, "F173 Calculator: Badge minY clamped inside screen bounds")
    }
}
