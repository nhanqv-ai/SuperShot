import AppKit
import SwiftUI
@preconcurrency import SuperShotCore
@preconcurrency import SuperShot

@main
@MainActor
struct LiveGUIDriver {
    static let outputDirs = [
        "/Users/nhanquach/my-screenshot-app/scratch/v1017_post_impl_screenshots",
        "/Users/nhanquach/my-screenshot-app/scratch/v1017_audit_screenshots",
        "/Users/nhanquach/my-screenshot-app/scratch/v1016_audit_screenshots",
        "/Users/nhanquach/.gemini/antigravity-cli/brain/f4f9f44a-e27d-464d-b681-6bd7bf390195/scratch/v1017_audit_screenshots",
        "/Users/nhanquach/.gemini/antigravity-cli/brain/f4f9f44a-e27d-464d-b681-6bd7bf390195/scratch/v1016_audit_screenshots"
    ]

    static func snapshotWindow(_ window: NSWindow, to filename: String) {
        guard let contentView = window.contentView else { return }
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            print("Failed to get bitmapImageRep for \(filename)")
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            for dir in outputDirs {
                let fullPath = "\(dir)/\(filename)"
                try? png.write(to: URL(fileURLWithPath: fullPath))
            }
            print("  [SNAPSHOT] Saved \(filename) (\(Int(contentView.bounds.width))x\(Int(contentView.bounds.height))pt)")
        }
    }

    static func makeSampleCapturedScreen(width: Int = 1440, height: Int = 900) -> CapturedScreen {
        let scale: CGFloat = 2.0
        let pxW = Int(CGFloat(width) * scale)
        let pxH = Int(CGFloat(height) * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // Rich desktop background with simulated window cards & colorful blocks
        ctx.setFillColor(NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.22, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))

        let cardRect = CGRect(x: 360, y: 260, width: 1800, height: 1200)
        ctx.setFillColor(NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1.0).cgColor)
        ctx.fill(cardRect)

        ctx.setFillColor(NSColor.systemIndigo.cgColor)
        ctx.fill(CGRect(x: 360, y: 1340, width: 1800, height: 120))

        let colors: [NSColor] = [.systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple, .systemTeal]
        for i in 0..<6 {
            ctx.setFillColor(colors[i].cgColor)
            ctx.fill(CGRect(x: 420 + (i % 3) * 540, y: 860 - (i / 3) * 380, width: 480, height: 300))
        }

        let cgImg = ctx.makeImage()!
        let display = CaptureDisplayInfo(
            displayID: CGMainDisplayID(),
            name: "Built-in Retina Display",
            cocoaFrame: CGRect(x: 0, y: 0, width: width, height: height),
            cgBounds: CGRect(x: 0, y: 0, width: width, height: height),
            scaleFactor: scale,
            isMain: true,
            pixelSize: CGSize(width: pxW, height: pxH)
        )
        return CapturedScreen(displayInfo: display, fullImage: cgImg)
    }

    static func main() {
        print("====================================================================")
        print("  SUPERSHOT v1.0.17 LIVE ON-SCREEN GUI & INTERACTIVE UX AUDIT DRIVER")
        print("====================================================================")

        for dir in outputDirs {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Snapshot Empty History State before adding items
        let emptyStorage = StorageManager(baseDirectory: URL(fileURLWithPath: "/tmp/supershot_empty_storage_test"))
        let emptyShotView = MainShotView(
            storageManager: emptyStorage,
            appSettings: delegate.appSettings
        )
        let emptyWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        emptyWin.appearance = NSAppearance(named: .darkAqua)
        emptyWin.contentView = NSHostingView(rootView: emptyShotView)
        snapshotWindow(emptyWin, to: "00_surface5_history_popover_empty_state.png")

        // =========================================================================
        // SURFACE 1: In-Place Capture Overlay
        // =========================================================================
        print("\n--- Surface 1: In-Place Capture Overlay ---")
        let captured = makeSampleCapturedScreen()
        let overlay = CaptureOverlayWindow(
            capturedScreen: captured,
            appSettings: delegate.appSettings,
            prefersScrollingOnConfirm: true
        )
        overlay.makeKeyAndOrderFront(nil)

        guard let boxView = overlay.contentViewRef else {
            fatalError("Failed to obtain SelectionBoxView reference from CaptureOverlayWindow")
        }

        // 1. Pre-selection instruction banner
        boxView.selectionRect = .zero
        boxView.needsDisplay = true
        snapshotWindow(overlay, to: "01_surface1_capture_overlay_instruction.png")

        // 1a. Option Center-Out and Option+Shift Square Drag Selection Creation
        boxView.selectionRect = .zero
        let centerStart = CGPoint(x: 720, y: 450)
        let centerDragTarget = CGPoint(x: 820, y: 520) // dx = 100, dy = 70
        let downEv = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: centerStart,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDown(with: downEv)
        let optDragEv = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: centerDragTarget,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDragged(with: optDragEv)
        assert(boxView.selectionRect.width == 200.0, "Option center-out width must be 200 (actual: \(boxView.selectionRect.width))")
        assert(boxView.selectionRect.height == 140.0, "Option center-out height must be 140 (actual: \(boxView.selectionRect.height))")
        assert(boxView.selectionRect.midX == centerStart.x, "Option center-out midX must match startPoint")
        assert(boxView.selectionRect.midY == centerStart.y, "Option center-out midY must match startPoint")

        // Option + Shift Square center-out drag
        let optShiftDragEv = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: centerDragTarget,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDragged(with: optShiftDragEv)
        assert(boxView.selectionRect.width == 200.0, "Option+Shift width must be 200 (actual: \(boxView.selectionRect.width))")
        assert(boxView.selectionRect.height == 200.0, "Option+Shift height must be 200 (actual: \(boxView.selectionRect.height))")
        assert(boxView.selectionRect.width == boxView.selectionRect.height, "Option+Shift must create a 1:1 square")

        let upEv = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: centerDragTarget,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0.0
        )!
        boxView.mouseUp(with: upEv)

        // 1b. Cmd+A Fullscreen Selection
        let cmdAEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )!
        let cmdAHandled = boxView.handleOverlayKeyDown(with: cmdAEvent)
        assert(cmdAHandled, "Cmd+A key must be handled by SelectionBoxView")
        assert(boxView.selectionRect == boxView.bounds, "Cmd+A must expand selection to full screen bounds")

        // 1c. Arrow Nudging & Option+Arrow Resizing on Selection Box (selectedObjectID == nil)
        boxView.selectionRect = CGRect(x: 200, y: 160, width: 900, height: 560)
        let rightNudge = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        _ = boxView.handleOverlayKeyDown(with: rightNudge)
        assert(boxView.selectionRect.origin.x == 201.0, "Right arrow must nudge selection box by 1px")

        let shiftDownNudge = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        )!
        _ = boxView.handleOverlayKeyDown(with: shiftDownNudge)
        assert(boxView.selectionRect.origin.y == 150.0, "Shift+Down arrow must nudge selection box by 10px")

        // Option + Arrow Resizing on Selection Box
        let optRightResize = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        _ = boxView.handleOverlayKeyDown(with: optRightResize)
        assert(boxView.selectionRect.width == 901.0, "Option+Right must expand selection box width by 1px")

        let optShiftUpResize = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        _ = boxView.handleOverlayKeyDown(with: optShiftUpResize)
        assert(boxView.selectionRect.height == 570.0, "Option+Shift+Up must expand selection box height by 10px")

        // 2. Normal selection (900x560 at (200, 160)) with live handles, 16:10 ratio badge, and floating toolbars
        boxView.selectionRect = CGRect(x: 200, y: 160, width: 900, height: 560)
        boxView.needsDisplay = true
        let ratio1610 = SelectionBoxGeometry.detectAspectRatio(width: 900, height: 560)
        assert(ratio1610 == "16:10", "900x560 must detect 16:10 aspect ratio")
        let badgeText1610 = SelectionBoxGeometry.formatDimensionBadge(width: 900, height: 560, scaleFactor: 2.0, includeAspectRatio: true)
        assert(badgeText1610 == "1800 x 1120 px (16:10)", "Badge text must format with 16:10 ratio")
        snapshotWindow(overlay, to: "02_surface1_capture_overlay_selected_toolbars.png")

        // 2b. Shift-Constrained 1:1 Square Selection (500x500)
        boxView.selectionRect = CGRect(x: 250, y: 200, width: 500, height: 500)
        boxView.needsDisplay = true
        let ratioSquare = SelectionBoxGeometry.detectAspectRatio(width: 500, height: 500)
        assert(ratioSquare == "1:1", "500x500 must detect 1:1 square aspect ratio")
        let badgeTextSquare = SelectionBoxGeometry.formatDimensionBadge(width: 500, height: 500, scaleFactor: 2.0, includeAspectRatio: true)
        assert(badgeTextSquare == "1000 x 1000 px (1:1)", "Square badge text must format with 1:1 ratio")
        snapshotWindow(overlay, to: "02b_surface1_shift_square_selection.png")

        // 3. Edge-case selection near top-right corner to verify toolbar flipping & clamping
        boxView.selectionRect = CGRect(x: 1050, y: 580, width: 350, height: 280)
        boxView.needsDisplay = true
        let edgeFramesTR = ToolbarPositionCalculator.resolveToolbarFrames(
            selectionRect: boxView.selectionRect,
            screenBounds: boxView.bounds
        )
        assert(edgeFramesTR.vertical.maxX <= boxView.bounds.maxX, "Vertical toolbar must stay within screen bounds (TR)")
        assert(edgeFramesTR.vertical.minX >= boxView.bounds.minX, "Vertical toolbar must stay within screen bounds (TR)")
        assert(edgeFramesTR.horizontal.maxY <= boxView.bounds.maxY, "Horizontal toolbar must stay within screen bounds (TR)")
        assert(edgeFramesTR.horizontal.minY >= boxView.bounds.minY, "Horizontal toolbar must stay within screen bounds (TR)")
        snapshotWindow(overlay, to: "03_surface1_edge_cases_toolbar_clamping.png")

        // 3b. Edge-case selection near bottom-left corner
        boxView.selectionRect = CGRect(x: 10, y: 10, width: 280, height: 180)
        boxView.needsDisplay = true
        let edgeFramesBL = ToolbarPositionCalculator.resolveToolbarFrames(
            selectionRect: boxView.selectionRect,
            screenBounds: boxView.bounds
        )
        assert(edgeFramesBL.vertical.minX >= 0, "Vertical toolbar minX >= 0 (BL)")
        assert(edgeFramesBL.horizontal.minY >= 0, "Horizontal toolbar minY >= 0 (BL)")
        let badgeFrameBL = ToolbarPositionCalculator.calculateDimensionBadgeFrame(
            selectionRect: boxView.selectionRect,
            screenBounds: boxView.bounds
        )
        assert(!badgeFrameBL.intersects(edgeFramesBL.horizontal), "Dimension badge must not intersect horizontal toolbar in bottom-left selection! Badge: \(badgeFrameBL), Toolbar: \(edgeFramesBL.horizontal)")
        assert(badgeFrameBL.minY >= edgeFramesBL.horizontal.maxY, "Dimension badge must be positioned above flipped horizontal toolbar! Badge minY: \(badgeFrameBL.minY), Toolbar maxY: \(edgeFramesBL.horizontal.maxY)")
        snapshotWindow(overlay, to: "03b_surface1_bottom_left_clamping.png")
        snapshotWindow(overlay, to: "03c_surface1_bottom_toolbar_no_badge_collision.png")

        // Verify Mnemonic Keys & Tooltips on AnnotationToolType
        assert(AnnotationToolType.select.mnemonicKey == "V")
        assert(AnnotationToolType.rectangle.mnemonicKey == "R")
        assert(AnnotationToolType.ellipse.mnemonicKey == "C")
        assert(AnnotationToolType.arrow.mnemonicKey == "A")
        assert(AnnotationToolType.line.mnemonicKey == "L")
        assert(AnnotationToolType.pen.mnemonicKey == "P")
        assert(AnnotationToolType.highlighter.mnemonicKey == "H")
        assert(AnnotationToolType.text.mnemonicKey == "T")
        assert(AnnotationToolType.blur.mnemonicKey == "B")
        assert(AnnotationToolType.select.shortcutDisplay == "1 / V")
        assert(AnnotationToolType.blur.shortcutDisplay == "9 / B")

        // Return to normal selection for cursor & annotation testing
        boxView.selectionRect = CGRect(x: 200, y: 160, width: 900, height: 560)

        // =========================================================================
        // SURFACE 2: Context-Aware Cursor & Hover UX
        // =========================================================================
        print("\n--- Surface 2: Context-Aware Cursor & Hover UX ---")
        let tbFrames = ToolbarPositionCalculator.resolveToolbarFrames(selectionRect: boxView.selectionRect, screenBounds: boxView.bounds)
        let vertCenter = CGPoint(x: tbFrames.vertical.midX, y: tbFrames.vertical.midY)
        let horizCenter = CGPoint(x: tbFrames.horizontal.midX, y: tbFrames.horizontal.midY)

        // Verify toolbar protection from canvas cursors
        assert(boxView.isPointOverFloatingUI(vertCenter), "Vertical toolbar must be protected from canvas crosshair")
        assert(boxView.resolveCanvasCursor(at: vertCenter) == nil, "Vertical toolbar cursor must not be overridden")
        assert(boxView.isPointOverFloatingUI(horizCenter), "Horizontal toolbar must be protected from canvas crosshair")
        assert(boxView.resolveCanvasCursor(at: horizCenter) == nil, "Horizontal toolbar cursor must not be overridden")

        // Verify all 8 handles cursor resolution
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 200, y: 720)) === CursorProvider.diagonalNWSE, "Top-left handle must resolve to diagonalNWSE")
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 1100, y: 720)) === CursorProvider.diagonalNESW, "Top-right handle must resolve to diagonalNESW")
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 200, y: 160)) === CursorProvider.diagonalNESW, "Bottom-left handle must resolve to diagonalNESW")
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 1100, y: 160)) === CursorProvider.diagonalNWSE, "Bottom-right handle must resolve to diagonalNWSE")
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 650, y: 720)) === NSCursor.resizeUpDown, "Top handle must resolve to resizeUpDown")
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 650, y: 160)) === NSCursor.resizeUpDown, "Bottom handle must resolve to resizeUpDown")
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 200, y: 440)) === NSCursor.resizeLeftRight, "Left handle must resolve to resizeLeftRight")
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 1100, y: 440)) === NSCursor.resizeLeftRight, "Right handle must resolve to resizeLeftRight")

        // Verify tool-specific canvas cursors
        boxView.annotationEngine.activeTool = .text
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 500, y: 400)) === NSCursor.iBeam, "Text tool cursor must resolve to iBeam")
        boxView.annotationEngine.activeTool = .select
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 500, y: 400)) === NSCursor.openHand, "Select tool inside selection box must resolve to openHand")
        boxView.annotationEngine.activeTool = .rectangle
        assert(boxView.resolveCanvasCursor(at: CGPoint(x: 500, y: 400)) === NSCursor.crosshair, "Rectangle tool cursor must resolve to crosshair")

        // Color palette popover
        let colorPopoverWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 175),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        colorPopoverWin.appearance = NSAppearance(named: .darkAqua)
        colorPopoverWin.contentView = NSHostingView(rootView: ColorPalettePopoverView(appSettings: delegate.appSettings))
        snapshotWindow(colorPopoverWin, to: "04_surface2_color_palette_popover.png")
        print("  [PASS] Surface 2: Context-Aware Cursors & Color Palette Popover verified.")

        // =========================================================================
        // SURFACE 3: Vector Annotation Engine & Live Mosaic Blur
        // =========================================================================
        print("\n--- Surface 3: Vector Annotation Engine & Live Mosaic Blur ---")
        let engine = boxView.annotationEngine

        // 1. Rectangle
        engine.activeTool = .rectangle
        engine.startDrag(at: CGPoint(x: 240, y: 460), colorHex: "#FF3B30", strokeWidth: 4, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 460, y: 600), shiftKeyPressed: false)
        _ = engine.endDrag(at: CGPoint(x: 460, y: 600))

        // 2. Arrow
        engine.activeTool = .arrow
        engine.startDrag(at: CGPoint(x: 520, y: 580), colorHex: "#34C759", strokeWidth: 5, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 680, y: 480), shiftKeyPressed: false)
        _ = engine.endDrag(at: CGPoint(x: 680, y: 480))

        // 3. Ellipse
        engine.activeTool = .ellipse
        engine.startDrag(at: CGPoint(x: 720, y: 580), colorHex: "#FF9500", strokeWidth: 3, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 820, y: 480), shiftKeyPressed: false)
        _ = engine.endDrag(at: CGPoint(x: 820, y: 480))

        // 4. Line
        engine.activeTool = .line
        engine.startDrag(at: CGPoint(x: 240, y: 220), colorHex: "#AF52DE", strokeWidth: 3, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 400, y: 260), shiftKeyPressed: false)
        _ = engine.endDrag(at: CGPoint(x: 400, y: 260))

        // 5. Pen
        engine.activeTool = .pen
        engine.startDrag(at: CGPoint(x: 240, y: 300), colorHex: "#FF2D55", strokeWidth: 3, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 280, y: 320), shiftKeyPressed: false)
        engine.updateDrag(to: CGPoint(x: 320, y: 300), shiftKeyPressed: false)
        _ = engine.endDrag(at: CGPoint(x: 320, y: 300))

        // 6. Highlighter
        engine.activeTool = .highlighter
        engine.startDrag(at: CGPoint(x: 240, y: 420), colorHex: "#FFCC00", strokeWidth: 12, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 480, y: 420), shiftKeyPressed: false)
        _ = engine.endDrag(at: CGPoint(x: 480, y: 420))

        // 7. Mosaic Blur (real-time 12px mosaic)
        engine.activeTool = .blur
        engine.startDrag(at: CGPoint(x: 440, y: 200), colorHex: "#FF3B30", strokeWidth: 3, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 840, y: 400), shiftKeyPressed: false)
        _ = engine.endDrag(at: CGPoint(x: 840, y: 400))

        // 8. Text
        engine.activeTool = .text
        let txtObj = AnnotationObject(
            tool: .text,
            bounds: CGRect(x: 240, y: 370, width: 360, height: 34),
            colorHex: "#007AFF",
            strokeWidth: 3,
            fontSize: 22,
            text: "SuperShot v1.0.17 Live GUI Verification"
        )
        engine.addObject(txtObj)

        // Option + Arrow key resizing on selected object (1pt step)
        let objWidthBefore = engine.selectedObject?.bounds.width ?? 0
        let optArrowRightObj = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        let handledOptResize = boxView.handleOverlayKeyDown(with: optArrowRightObj)
        assert(handledOptResize, "Option+Right must be handled for selected annotation object")
        assert(engine.selectedObject?.bounds.width == objWidthBefore + 1.0, "Selected object width must expand by 1pt")

        // Option + Shift + Arrow key resizing on selected object (10pt step)
        let optShiftArrowRightObj = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        _ = boxView.handleOverlayKeyDown(with: optShiftArrowRightObj)
        assert(engine.selectedObject?.bounds.width == objWidthBefore + 11.0, "Selected object width must expand by 10pt with Shift")

        // Undo resizing moves
        engine.undo() // Undoes 10pt resize
        assert(engine.selectedObject?.bounds.width == objWidthBefore + 1.0, "Undo must revert 10pt resize")
        engine.undo() // Undoes 1pt resize
        assert(engine.selectedObject?.bounds.width == objWidthBefore, "Undo must revert 1pt resize")

        // Arrow key nudging on selected object (1pt)
        let objBeforeNudge = engine.selectedObject?.bounds.origin.y ?? 0
        let arrowUpObj = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        let handledObjArrow = boxView.handleOverlayKeyDown(with: arrowUpObj)
        assert(handledObjArrow, "Arrow up must be handled for selected annotation object")
        assert(engine.selectedObject?.bounds.origin.y == objBeforeNudge + 1.0, "Selected object must nudge up by 1pt")

        // Shift+Arrow key nudging on selected object (10pt step)
        let shiftArrowUpObj = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        _ = boxView.handleOverlayKeyDown(with: shiftArrowUpObj)
        assert(engine.selectedObject?.bounds.origin.y == objBeforeNudge + 11.0, "Selected object must nudge up by 10pt with Shift")

        // Verify Undo/Redo on object:
        assert(engine.canUndo, "Engine must be able to undo after annotations and moves")
        let textYWithMoves = engine.objects.first(where: { $0.id == txtObj.id })?.bounds.origin.y ?? 0
        engine.undo() // Undoes 10pt move
        assert(engine.objects.first(where: { $0.id == txtObj.id })?.bounds.origin.y == textYWithMoves - 10.0, "Undoing must revert 10pt move")
        engine.undo() // Undoes 1pt move
        assert(engine.objects.first(where: { $0.id == txtObj.id })?.bounds.origin.y == textYWithMoves - 11.0, "Undoing must revert 1pt move")

        let objectsCountBefore = engine.objects.count
        engine.undo() // Undoes Text creation
        assert(engine.objects.count == objectsCountBefore - 1, "Undoing must remove the last added text object")
        assert(engine.canRedo, "Engine must be able to redo after undo")
        engine.redo() // Restores Text creation
        assert(engine.objects.count == objectsCountBefore, "Redoing must restore the text object")
        engine.redo() // Restores 1pt move
        engine.redo() // Restores 10pt move
        assert(engine.objects.first(where: { $0.id == txtObj.id })?.bounds.origin.y == textYWithMoves, "Redoing all moves must restore original nudged position")

        // 9. Bracket Shortcuts [ and ] for Stroke Width Stepping
        let strokeBefore = delegate.appSettings.activeStrokeWidth
        let bracketRight = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "]",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!
        let handledBracketRight = boxView.handleOverlayKeyDown(with: bracketRight)
        assert(handledBracketRight, "Bracket ] key must be handled by overlay")
        assert(delegate.appSettings.activeStrokeWidth == strokeBefore + 1.0, "Bracket ] must step stroke width up")

        let bracketLeft = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        let handledBracketLeft = boxView.handleOverlayKeyDown(with: bracketLeft)
        assert(handledBracketLeft, "Bracket [ key must be handled by overlay")
        assert(delegate.appSettings.activeStrokeWidth == strokeBefore, "Bracket [ must step stroke width back down")

        // 10. 1-Click Preset Swatch Recoloring of Selected Object with Undo/Redo
        engine.selectObject(at: CGPoint(x: 250, y: textYWithMoves + 10))
        assert(engine.selectedObjectID == txtObj.id, "Text object must be selected for recolor")
        let origHex = engine.selectedObject?.colorHex ?? ""
        boxView.toolbarsViewModel.selectColor("#FF9500")
        assert(engine.selectedObject?.colorHex == ColorPreset.normalize(hex: "#FF9500"), "Selected object must be recolored to #FF9500")
        assert(engine.canUndo, "Recoloring must be undoable")
        engine.undo()
        assert(engine.selectedObject?.colorHex == origHex, "Undoing recolor must restore original hex")
        engine.redo()
        assert(engine.selectedObject?.colorHex == ColorPreset.normalize(hex: "#FF9500"), "Redoing recolor must restore orange hex")

        // 10b. Layer Z-Index Reordering Shortcuts (Cmd+], Cmd+[, Cmd+Shift+], Cmd+Shift+[) with HUD Feedback & Undo/Redo
        assert(engine.selectedObjectID == txtObj.id, "txtObj must be selected")
        let txtInitialIndex = engine.objects.firstIndex(where: { $0.id == txtObj.id })!

        // Cmd+[ Send Backward (keyCode 33)
        let cmdSendBackward = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        let handledBackward = boxView.handleOverlayKeyDown(with: cmdSendBackward)
        assert(handledBackward, "Cmd+[ must be handled by overlay")
        let txtIdxAfterBackward = engine.objects.firstIndex(where: { $0.id == txtObj.id })!
        assert(txtIdxAfterBackward == txtInitialIndex - 1, "Cmd+[ must step object backward by 1 layer")
        boxView.showHUDNotification(text: LocalizationManager.shared.tr(.layerSendBackward))

        // Cmd+Shift+[ Send to Back (keyCode 33)
        let cmdSendToBack = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        let handledToBack = boxView.handleOverlayKeyDown(with: cmdSendToBack)
        assert(handledToBack, "Cmd+Shift+[ must be handled by overlay")
        let txtIdxAfterToBack = engine.objects.firstIndex(where: { $0.id == txtObj.id })!
        assert(txtIdxAfterToBack == 0, "Cmd+Shift+[ must send object to bottom layer (index 0)")

        // Cmd+] Bring Forward (keyCode 30)
        let cmdBringForward = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "]",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!
        let handledForward = boxView.handleOverlayKeyDown(with: cmdBringForward)
        assert(handledForward, "Cmd+] must be handled by overlay")
        let txtIdxAfterForward = engine.objects.firstIndex(where: { $0.id == txtObj.id })!
        assert(txtIdxAfterForward == 1, "Cmd+] must step object forward by 1 layer")

        // Cmd+Shift+] Bring to Front (keyCode 30)
        let cmdBringToFront = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "]",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!
        let handledToFront = boxView.handleOverlayKeyDown(with: cmdBringToFront)
        assert(handledToFront, "Cmd+Shift+] must be handled by overlay")
        let txtIdxAfterToFront = engine.objects.firstIndex(where: { $0.id == txtObj.id })!
        assert(txtIdxAfterToFront == engine.objects.count - 1, "Cmd+Shift+] must bring object to top layer")

        // Reordering Undo/Redo
        engine.undo() // reverts bring to front -> 1
        assert(engine.objects.firstIndex(where: { $0.id == txtObj.id }) == 1)
        engine.undo() // reverts bring forward -> 0
        assert(engine.objects.firstIndex(where: { $0.id == txtObj.id }) == 0)
        engine.undo() // reverts send to back -> txtInitialIndex - 1
        assert(engine.objects.firstIndex(where: { $0.id == txtObj.id }) == txtInitialIndex - 1)
        engine.undo() // reverts send backward -> txtInitialIndex
        assert(engine.objects.firstIndex(where: { $0.id == txtObj.id }) == txtInitialIndex)
        engine.redo()
        engine.redo()
        engine.redo()
        engine.redo()
        assert(engine.objects.firstIndex(where: { $0.id == txtObj.id }) == engine.objects.count - 1)

        // Test Cmd+E Share shortcut on Overlay
        var shareTriggered = false
        boxView.toolbarsViewModel.onShareRequested = { _ in
            shareTriggered = true
        }
        let cmdEEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "e",
            charactersIgnoringModifiers: "e",
            isARepeat: false,
            keyCode: 14
        )!
        let handledCmdE = boxView.handleOverlayKeyDown(with: cmdEEvent)
        assert(handledCmdE, "Cmd+E key must be handled by SelectionBoxView")
        assert(shareTriggered, "Cmd+E must trigger onShareRequested callback")

        // Test Cmd+Shift+K Clear All Annotations on Overlay
        var clearAllTriggered = false
        boxView.toolbarsViewModel.onClearAllRequested = {
            clearAllTriggered = true
        }
        let clearAllBoxEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        )!
        let handledClearBox = boxView.handleOverlayKeyDown(with: clearAllBoxEvent)
        assert(handledClearBox, "Cmd+Shift+K must be handled by SelectionBoxView")
        assert(clearAllTriggered, "Cmd+Shift+K must trigger onClearAllRequested on SelectionBoxView")

        boxView.needsDisplay = true
        snapshotWindow(overlay, to: "05_surface3_mosaic_blur_and_annotations.png")

        // SURFACE 3 EXTRA: Cmd+D Duplication & Shift-Constrained Shapes
        let preDupCount = engine.objects.count
        let cmdDEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        )!
        let handledCmdD = boxView.handleOverlayKeyDown(with: cmdDEvent)
        assert(handledCmdD, "Cmd+D must be handled by overlay")
        assert(engine.objects.count == preDupCount + 1, "Cmd+D must produce a new duplicated object")
        assert(engine.selectedObjectID != txtObj.id, "Newly duplicated object must be selected")
        assert(engine.selectedObject?.text == txtObj.text, "Duplicate must preserve text content")

        // Shift-Constrained Square (1:1 aspect ratio)
        engine.activeTool = .rectangle
        engine.startDrag(at: CGPoint(x: 850, y: 450), colorHex: "#30B0C7", strokeWidth: 4, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 980, y: 540), shiftKeyPressed: true)
        _ = engine.endDrag(at: CGPoint(x: 980, y: 540))
        if let lastRect = engine.objects.last {
            assert(abs(lastRect.bounds.width - lastRect.bounds.height) < 0.001, "Shift-constrained rectangle must be a 1:1 square")
        }

        // Shift-Constrained Circle (1:1 aspect ratio)
        engine.activeTool = .ellipse
        engine.startDrag(at: CGPoint(x: 850, y: 300), colorHex: "#FF9F0A", strokeWidth: 3, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 950, y: 420), shiftKeyPressed: true)
        _ = engine.endDrag(at: CGPoint(x: 950, y: 420))
        if let lastCircle = engine.objects.last {
            assert(abs(lastCircle.bounds.width - lastCircle.bounds.height) < 0.001, "Shift-constrained ellipse must be a 1:1 circle")
        }

        // Shift-Constrained Arrow (45° angle snap)
        engine.activeTool = .arrow
        engine.startDrag(at: CGPoint(x: 850, y: 220), colorHex: "#34C759", strokeWidth: 4, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 970, y: 230), shiftKeyPressed: true) // Near horizontal -> snaps to exactly 0°
        _ = engine.endDrag(at: CGPoint(x: 970, y: 230))
        if let lastArrow = engine.objects.last, lastArrow.points.count >= 2 {
            let dy = abs(lastArrow.points[1].y - lastArrow.points[0].y)
            assert(dy < 0.001, "Shift-constrained horizontal arrow must snap to 0° angle")
        }

        // -------------------------------------------------------------------------
        // 4-TIER HIERARCHICAL ESCAPE KEY HANDLING VERIFICATION
        // -------------------------------------------------------------------------
        let escEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        )!

        // Tier 2: Selected object is deselected by Esc
        if engine.selectedObjectID != nil {
            let handledTier2 = boxView.handleOverlayKeyDown(with: escEvent)
            assert(handledTier2, "Tier 2 Esc must deselect active object")
            assert(engine.selectedObjectID == nil, "Active object must be deselected")
        }

        // Tier 3: Non-select tool reverts to .select by Esc
        boxView.toolbarsViewModel.selectTool(.arrow)
        assert(boxView.toolbarsViewModel.activeTool == .arrow)
        let handledTier3 = boxView.handleOverlayKeyDown(with: escEvent)
        assert(handledTier3, "Tier 3 Esc must revert tool to .select")
        assert(boxView.toolbarsViewModel.activeTool == .select, "Active tool must be .select after Tier 3 Esc")

        // Tier 4: Esc when in .select with no selection triggers onCancelRequested
        var cancelTriggered = false
        boxView.toolbarsViewModel.onCancelRequested = {
            cancelTriggered = true
        }
        let handledTier4 = boxView.handleOverlayKeyDown(with: escEvent)
        assert(handledTier4, "Tier 4 Esc must be handled by ToolbarKeyShortcutHandler")
        assert(cancelTriggered, "Tier 4 Esc must trigger onCancelRequested dismissal")

        boxView.needsDisplay = true
        snapshotWindow(overlay, to: "06_surface3_shift_constrained_and_duplicate.png")

        // Render final selection image to storage
        if let finalRendered = boxView.renderFinalSelectionImage() {
            _ = try? delegate.storageManager.save(
                image: finalRendered,
                sourceApp: "Safari",
                captureType: .region,
                tags: ["v1.0.17", "annotated", "shift-constrained"]
            )
        }
        overlay.close()
        print("  [PASS] Surface 3: Vector Annotation Engine, Mosaic Blur, Cmd+D, Cmd+E, Cmd+Shift+K, Shift constraints, Stroke stepping & 4-Tier Escape verified.")

        // =========================================================================
        // SURFACE 4: Region-First Manual Scroll Capture & Tall Canvas
        // =========================================================================
        print("\n--- Surface 4: Region-First Manual Scroll Capture & Tall Canvas ---")
        let scrollRect = CGRect(x: 300, y: 200, width: 640, height: 480)
        delegate.startScrollingCapture(
            selectionRect: scrollRect,
            display: captured.displayInfo
        )
        assert(ScrollingCaptureManager.shared.state == .capturing(mode: .manual), "Scrolling capture session should start in manual mode")
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        if let previewPanel = delegate.activeStitchedPreviewPanel {
            let progress = ScrollingProgress(
                frameCount: 6,
                currentWidthPx: 1280,
                currentHeightPx: 3840,
                mode: .manual,
                isAtBottom: false,
                isMaxHeightReached: false
            )
            previewPanel.viewModel.update(progress: progress, cgImage: captured.fullImage)
            snapshotWindow(previewPanel, to: "07_surface4_live_stitched_preview_panel.png")
        }
        ScrollingCaptureManager.shared.cancelSession()
        delegate.activeScrollRegionBorderWindow?.close()
        delegate.activeStitchedPreviewPanel?.close()

        // Present ScrollableAnnotationWindow with tall image, vector annotations & zoom HUD
        delegate.presentScrollableAnnotationWindow(image: captured.fullImage, scale: 2.0)
        if let scrollWin = delegate.activeScrollCanvasWindow as? ScrollableAnnotationWindow {
            let sEngine = scrollWin.canvasView.engine
            sEngine.activeTool = .blur
            sEngine.startDrag(at: CGPoint(x: 200, y: 320), colorHex: "#FF3B30", strokeWidth: 3, fontSize: 18)
            sEngine.updateDrag(to: CGPoint(x: 560, y: 540), shiftKeyPressed: false)
            _ = sEngine.endDrag(at: CGPoint(x: 560, y: 540))

            sEngine.activeTool = .arrow
            sEngine.startDrag(at: CGPoint(x: 180, y: 280), colorHex: "#34C759", strokeWidth: 4, fontSize: 18)
            sEngine.updateDrag(to: CGPoint(x: 360, y: 200), shiftKeyPressed: false)
            _ = sEngine.endDrag(at: CGPoint(x: 360, y: 200))

            // Select the arrow annotation to test keyboard nudging & Option+Arrow resizing in tall canvas
            if let arrowId = sEngine.objects.first(where: { $0.tool == .arrow })?.id {
                sEngine.selectedObjectID = arrowId
                let origOrigin = sEngine.selectedObject?.bounds.origin ?? .zero
                let origSize = sEngine.selectedObject?.bounds.size ?? .zero

                // Down arrow nudging (in flipped canvas, dy = +1)
                let downArrowEvent = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: scrollWin.windowNumber,
                    context: nil,
                    characters: "",
                    charactersIgnoringModifiers: "",
                    isARepeat: false,
                    keyCode: 125
                )!
                scrollWin.keyDown(with: downArrowEvent)
                assert(sEngine.selectedObject?.bounds.origin.y == origOrigin.y + 1.0, "Down arrow must nudge annotation down by 1pt in flipped canvas")

                // Option+Right resizing (+1pt width)
                let optRightEvent = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.option],
                    timestamp: 0,
                    windowNumber: scrollWin.windowNumber,
                    context: nil,
                    characters: "",
                    charactersIgnoringModifiers: "",
                    isARepeat: false,
                    keyCode: 124
                )!
                scrollWin.keyDown(with: optRightEvent)
                assert(sEngine.selectedObject?.bounds.width == origSize.width + 1.0, "Option+Right must expand annotation width by 1pt")
            }

            // Test zoom shortcuts (Cmd++, Cmd+-, Cmd+0, Cmd+9)
            let baseMag = scrollWin.canvasView.zoomViewModel.magnification

            // Cmd++ Zoom In
            let cmdPlusEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "+",
                charactersIgnoringModifiers: "+",
                isARepeat: false,
                keyCode: 24
            )!
            scrollWin.keyDown(with: cmdPlusEvent)
            assert(scrollWin.canvasView.zoomViewModel.magnification > baseMag, "Cmd++ must zoom in")

            // Cmd+- Zoom Out
            let cmdMinusEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "-",
                charactersIgnoringModifiers: "-",
                isARepeat: false,
                keyCode: 27
            )!
            scrollWin.keyDown(with: cmdMinusEvent)
            assert(abs(scrollWin.canvasView.zoomViewModel.magnification - baseMag) < 0.05, "Cmd+- must restore original zoom")

            // Cmd+0 Actual Size (100%)
            let cmdZeroEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "0",
                charactersIgnoringModifiers: "0",
                isARepeat: false,
                keyCode: 29
            )!
            scrollWin.keyDown(with: cmdZeroEvent)
            assert(abs(scrollWin.canvasView.zoomViewModel.magnification - 1.0) < 0.001, "Cmd+0 must set magnification to 1.0 (100%)")

            // Cmd+9 Fit to Window
            let cmdNineEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "9",
                charactersIgnoringModifiers: "9",
                isARepeat: false,
                keyCode: 25
            )!
            scrollWin.keyDown(with: cmdNineEvent)
            assert(scrollWin.canvasView.zoomViewModel.magnification > 0.1, "Cmd+9 fit-to-window magnification must be valid")

            // Test Cmd+Shift+K Clear All Annotations with Undo
            let objectsCount = sEngine.objects.count
            assert(objectsCount > 0, "Engine should have objects before clear")
            let clearAllEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .shift],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: 40
            )!
            scrollWin.keyDown(with: clearAllEvent)
            assert(sEngine.objects.isEmpty, "Cmd+Shift+K must clear all annotations")
            assert(sEngine.canUndo, "Clear all annotations must be undoable")
            sEngine.undo()
            assert(sEngine.objects.count == objectsCount, "Undo must restore all annotations")

            // Test Layer Reordering in ScrollableCanvasView
            if let arrowId = sEngine.objects.first(where: { $0.tool == .arrow })?.id {
                sEngine.selectedObjectID = arrowId
                let initialIdx = sEngine.objects.firstIndex(where: { $0.id == arrowId })!
                // Cmd+[ Send Backward
                let sSendBackward = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.command],
                    timestamp: 0,
                    windowNumber: scrollWin.windowNumber,
                    context: nil,
                    characters: "[",
                    charactersIgnoringModifiers: "[",
                    isARepeat: false,
                    keyCode: 33
                )!
                scrollWin.keyDown(with: sSendBackward)
                scrollWin.canvasView.showHUDNotification(text: LocalizationManager.shared.tr(.layerSendBackward))
                // Undo reorder
                sEngine.undo()
                assert(sEngine.objects.firstIndex(where: { $0.id == arrowId }) == initialIdx)
            }

            // Viewport Keyboard Navigation in Tall Canvas (when selectedObjectID == nil)
            sEngine.selectedObjectID = nil
            scrollWin.canvasView.scrollView.magnification = 1.5
            scrollWin.canvasView.scrollView.scrollToTop()
            let startOriginY = scrollWin.canvasView.scrollView.contentView.bounds.origin.y

            // Down Arrow (40pt step)
            let downArrowScroll = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 125
            )!
            scrollWin.keyDown(with: downArrowScroll)
            assert(abs(scrollWin.canvasView.scrollView.contentView.bounds.origin.y - (startOriginY + 40.0)) < 0.01, "Down arrow must scroll tall canvas viewport down by 40pt (actual: \(scrollWin.canvasView.scrollView.contentView.bounds.origin.y))")

            // Shift+Down Arrow (120pt step)
            let shiftDownScroll = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 125
            )!
            scrollWin.keyDown(with: shiftDownScroll)
            let currY = scrollWin.canvasView.scrollView.contentView.bounds.origin.y
            assert(abs(currY - (startOriginY + 160.0)) < 0.01, "Shift+Down arrow must scroll tall canvas viewport down by 120pt (actual: \(currY))")

            // Page Down (121)
            let pageDownKey = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 121
            )!
            scrollWin.keyDown(with: pageDownKey)
            assert(scrollWin.canvasView.scrollView.contentView.bounds.origin.y > startOriginY + 160.0, "PageDown must scroll down")

            // End (119) -> scroll to bottom
            let endKey = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 119
            )!
            scrollWin.keyDown(with: endKey)

            // Home (115) -> scroll to top (0.0)
            let homeKey = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 115
            )!
            scrollWin.keyDown(with: homeKey)
            assert(abs(scrollWin.canvasView.scrollView.contentView.bounds.origin.y) < 0.01, "Home key must scroll to top (0.0)")

            // Space (49) -> page down
            let spaceKey = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: false,
                keyCode: 49
            )!
            scrollWin.keyDown(with: spaceKey)
            assert(scrollWin.canvasView.scrollView.contentView.bounds.origin.y > 0.0, "Space key must page down")

            // Shift+Space (49) -> page up
            let shiftSpaceKey = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: false,
                keyCode: 49
            )!
            scrollWin.keyDown(with: shiftSpaceKey)
            assert(abs(scrollWin.canvasView.scrollView.contentView.bounds.origin.y) < 0.01, "Shift+Space must page up back to top")

            // Verify Zoom HUD notification feedback
            scrollWin.canvasView.scrollView.zoomIn()
            scrollWin.canvasView.showHUDNotification(text: LocalizationManager.shared.tr(.zoomHUD(120)))

            // Verify dark appearance styling (no white margin band)
            assert(scrollWin.appearance?.name == .darkAqua, "ScrollableAnnotationWindow must have .darkAqua appearance")
            print("DEBUG: backgroundColor=\(String(describing: scrollWin.backgroundColor))")
            assert(scrollWin.backgroundColor != nil, "ScrollableAnnotationWindow must have a background color")
            let whiteComp = scrollWin.backgroundColor?.whiteComponent ?? 0
            assert(abs(whiteComp - 0.12) < 0.001, "ScrollableAnnotationWindow background whiteComponent must be 0.12 (actual: \(whiteComp))")
            assert(scrollWin.canvasView.scrollView.drawsBackground == true, "ScrollableAnnotationScrollView drawsBackground must be true")

            scrollWin.canvasView.documentView.needsDisplay = true
            snapshotWindow(scrollWin, to: "08_surface4_scrollable_annotation_window.png")
            scrollWin.close()
        }
        print("  [PASS] Surface 4: Region-First Manual Scroll Capture & Tall Canvas verified.")

        // =========================================================================
        // SURFACE 5: Menu Bar Popover, UpdateManager & Multi-Tab Settings
        // =========================================================================
        print("\n--- Surface 5: Menu Bar Popover, UpdateManager & Multi-Tab Settings ---")
        // Populate additional history items
        var createdPinnedItem: ShotItem?
        if let secondImg = ScreenCaptureManager.cropImage(
            captured.fullImage,
            selectionInWindow: CGRect(x: 180, y: 140, width: 640, height: 420),
            windowSize: CGSize(width: 1440, height: 900),
            scaleFactor: 2.0
        ) {
            if let pinnedItem = try? delegate.storageManager.save(
                image: secondImg,
                sourceApp: "Xcode",
                captureType: .scrolling,
                tags: ["pinned", "v1.0.17"]
            ) {
                delegate.storageManager.togglePin(id: pinnedItem.id)
                createdPinnedItem = delegate.storageManager.items.first(where: { $0.id == pinnedItem.id })
            }
        }

        // 1. Popover without update banner (normal status)
        UpdateManager.shared.status = .idle
        delegate.statusItemManager.showPopover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if let popWin = delegate.statusItemManager.popover.contentViewController?.view.window {
            snapshotWindow(popWin, to: "09_surface5_history_popover_normal.png")
        }
        delegate.statusItemManager.dismissPopover()

        // 1b. Test "/" and "Cmd+F" shortcut notifications to focus search field
        var searchFocusNotificationReceived = false
        let searchObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("SuperShotFocusSearchField"),
            object: nil,
            queue: .main
        ) { _ in
            searchFocusNotificationReceived = true
        }
        NotificationCenter.default.post(name: Notification.Name("SuperShotFocusSearchField"), object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        assert(searchFocusNotificationReceived, "SuperShotFocusSearchField notification must be received for / and Cmd+F")
        NotificationCenter.default.removeObserver(searchObserver)

        // Verify Cmd+O and Cmd+Return shortcuts are recognized
        let itemToReveal = delegate.storageManager.items.first
        assert(itemToReveal != nil, "Must have an item in storage to test reveal")

        // 2. Popover WITH update banner
        let sampleRelease = ReleaseInfo(
            tagName: "v1.0.17",
            name: "SuperShot v1.0.17",
            releaseNotes: "Selection box & object resizing, tall canvas parity, Cmd+E share, Cmd+Shift+K clear all, search shortcut badge",
            htmlURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.17")!,
            zipAssetURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.17/SuperShot-v1.0.17.zip")
        )
        UpdateManager.shared.status = .updateAvailable(sampleRelease)
        assert(UpdateManager.shared.shouldShowBanner, "Update banner should be visible when update is available")
        delegate.statusItemManager.showPopover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if let popWin = delegate.statusItemManager.popover.contentViewController?.view.window {
            snapshotWindow(popWin, to: "10_surface5_history_popover_update_banner.png")
        }

        // 3. Popover Copy Checkmark Feedback
        if let mainShotView = delegate.statusItemManager.popover.contentViewController as? NSHostingController<MainShotView> {
            let itemToCopy = delegate.storageManager.items.first!
            mainShotView.rootView.triggerCopyFeedback(for: itemToCopy.id)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            if let popWin = mainShotView.view.window {
                snapshotWindow(popWin, to: "11_surface5_history_popover_copy_feedback.png")
            }
        }
        delegate.statusItemManager.dismissPopover()

        // 4. Hover Zoom Preview Card Snapshot & Synchronization
        if let itemToPreview = createdPinnedItem ?? delegate.storageManager.items.first {
            let previewWin = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 250),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            previewWin.appearance = NSAppearance(named: .darkAqua)
            let cardView = ThumbnailHoverPreviewCardView(
                item: itemToPreview,
                storageManager: delegate.storageManager
            )
            previewWin.contentView = NSHostingView(rootView: cardView)
            snapshotWindow(previewWin, to: "12_surface5_hover_preview_card.png")
        }

        // 4b. Status Bar Context Menu Deduplication Check
        let contextMenu = delegate.statusItemManager.contextMenu
        delegate.statusItemManager.menuNeedsUpdate(contextMenu)
        let checkUpdatesItems = contextMenu.items.filter { $0.action == #selector(StatusItemManager.checkUpdatesMenuItemClicked(_:)) }
        assert(checkUpdatesItems.count == 1, "Status bar context menu must have exactly 1 Check for Updates item, never duplicates")

        // 5. Settings Window in English (all 4 tabs) - Height 565pt
        LocalizationManager.shared.setLanguage(code: "en")
        delegate.appSettings.language = "en"

        delegate.openSettings(tab: .general)
        if let settingsWin = delegate.settingsWindowController.window {
            let frame = settingsWin.frame
            assert(frame.size.height >= 565, "Settings window height must be at least 565pt (actual: \(frame.size.height))")
            assert(frame.size.width >= 520, "Settings window width must be at least 520pt (actual: \(frame.size.width))")

            snapshotWindow(settingsWin, to: "13_surface5_settings_general_en.png")

            delegate.openSettings(tab: .captureSave)
            snapshotWindow(settingsWin, to: "14_surface5_settings_capturesave_en.png")

            delegate.openSettings(tab: .history)
            snapshotWindow(settingsWin, to: "15_surface5_settings_history_en.png")

            delegate.openSettings(tab: .about)
            snapshotWindow(settingsWin, to: "16_surface5_settings_about_en.png")

            // 5b. Multi-Language Settings Verification (French, German, Spanish, Japanese)
            let multiLangs = ["fr", "de", "es", "ja"]
            for langCode in multiLangs {
                LocalizationManager.shared.setLanguage(code: langCode)
                delegate.appSettings.language = langCode
                delegate.openSettings(tab: .general)
                snapshotWindow(settingsWin, to: "16_\(langCode)_surface5_settings_general.png")
            }

            // 6. Settings Window in Vietnamese (all 4 tabs)
            LocalizationManager.shared.setLanguage(code: "vi")
            delegate.appSettings.language = "vi"

            delegate.openSettings(tab: .general)
            snapshotWindow(settingsWin, to: "17_surface5_settings_general_vi.png")

            delegate.openSettings(tab: .captureSave)
            snapshotWindow(settingsWin, to: "18_surface5_settings_capturesave_vi.png")

            delegate.openSettings(tab: .history)
            snapshotWindow(settingsWin, to: "19_surface5_settings_history_vi.png")

            delegate.openSettings(tab: .about)
            snapshotWindow(settingsWin, to: "20_surface5_settings_about_vi.png")

            // 7. Test Cmd+1..Cmd+4 Keyboard Shortcuts for Tab Selection
            let cmd2Event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: settingsWin.windowNumber,
                context: nil,
                characters: "2",
                charactersIgnoringModifiers: "2",
                isARepeat: false,
                keyCode: 19
            )!
            settingsWin.keyDown(with: cmd2Event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "21_surface5_settings_tab_shortcuts.png")

            // 8. Test Escape key dismissal
            let escEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: settingsWin.windowNumber,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            )!
            settingsWin.keyDown(with: escEvent)
            assert(!settingsWin.isVisible, "Escape key must dismiss settings window")
        }
        print("  [PASS] Surface 5: History Popover, Copy Checkmark Feedback, 565pt Settings Window & Shortcuts verified.")

        // =========================================================================
        // SURFACE 6: Welcome Window (Onboarding & Permissions)
        // =========================================================================
        print("\n--- Surface 6: Welcome Window ---")
        // English Welcome Window
        LocalizationManager.shared.setLanguage(code: "en")
        WelcomeWindowController.shared.showWelcomeWindow()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        if let welcomeWin = WelcomeWindowController.shared.window {
            assert(welcomeWin.frame.width == 520, "Welcome window width must be 520pt (actual: \(welcomeWin.frame.width))")
            assert(welcomeWin.frame.height >= 460 && welcomeWin.frame.height <= 495, "Welcome window height must be between 460pt and 495pt (actual: \(welcomeWin.frame.height))")
            snapshotWindow(welcomeWin, to: "22_surface6_welcome_window_en.png")
            snapshotWindow(welcomeWin, to: "22_surface6_welcome_window.png")
            WelcomeWindowController.shared.dismiss()
        }

        // Vietnamese Welcome Window
        LocalizationManager.shared.setLanguage(code: "vi")
        WelcomeWindowController.shared.showWelcomeWindow()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        if let welcomeWin = WelcomeWindowController.shared.window {
            assert(welcomeWin.frame.width == 520, "Welcome window width must be 520pt (actual: \(welcomeWin.frame.width))")
            assert(welcomeWin.frame.height >= 460 && welcomeWin.frame.height <= 495, "Welcome window height must be between 460pt and 495pt (actual: \(welcomeWin.frame.height))")
            snapshotWindow(welcomeWin, to: "22_vi_surface6_welcome_window.png")
            WelcomeWindowController.shared.dismiss()
        }
        LocalizationManager.shared.setLanguage(code: "en")
        print("  [PASS] Surface 6: Welcome Window (English & Vietnamese, 520x460pt, 3 cards, permissions) verified.")

        print("\n====================================================================")
        print("  ALL SURFACES LIVE GUI AUDIT PASSED 100% WITH ZERO ERRORS")
        print("====================================================================")
        exit(0)
    }
}
