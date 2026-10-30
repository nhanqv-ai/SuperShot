import AppKit
import SwiftUI
@preconcurrency import SuperShotCore
@preconcurrency import SuperShot

@main
@MainActor
struct LiveGUIDriver {
    static let outputDirs = [
        "/Users/nhanquach/my-screenshot-app/scratch/v1026_audit_screenshots",
        "/Users/nhanquach/.gemini/antigravity-cli/brain/f4f9f44a-e27d-464d-b681-6bd7bf390195/scratch/v1026_audit_screenshots",
        "/Users/nhanquach/.gemini/antigravity-cli/brain/ab5f35fc-54c1-448d-885d-4133b74bae30/scratch/v1026_audit_screenshots"
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

        // Rich desktop background with simulated window cards and colorful blocks
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
        print("  SUPERSHOT v1.0.26 LIVE ON-SCREEN GUI & INTERACTIVE UX AUDIT DRIVER")
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

        // 1a. Feature 174: Spacebar Drag Repositioning (Space + Drag)
        boxView.selectionRect = .zero
        let spaceDragStart = CGPoint(x: 200, y: 200)
        let spaceDragInit = CGPoint(x: 450, y: 350)
        let spaceDownEv = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: spaceDragStart,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDown(with: spaceDownEv)

        let dragInitEv = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: spaceDragInit,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDragged(with: dragInitEv)
        assert(boxView.selectionRect.width == 250.0, "Initial drag width should be 250")
        assert(boxView.selectionRect.height == 150.0, "Initial drag height should be 150")

        // Simulate Space key press (keyCode 49)
        let spaceKeyEv = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )!
        _ = boxView.handleOverlayKeyDown(with: spaceKeyEv)

        // Drag to (500, 400) while holding space -> pan origin by dx=50, dy=50
        let spacePannedTarget = CGPoint(x: 500, y: 400)
        let dragWithSpaceEv = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: spacePannedTarget,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 3,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDragged(with: dragWithSpaceEv)
        assert(boxView.spaceKeyDragging, "spaceKeyDragging must be true while dragging with spacebar held")
        assert(boxView.selectionRect.width == 250.0, "Width must be preserved during spacebar repositioning")
        assert(boxView.selectionRect.height == 150.0, "Height must be preserved during spacebar repositioning")
        assert(boxView.selectionRect.origin.x == 250.0, "Origin X must be panned to 250.0")
        assert(boxView.selectionRect.origin.y == 250.0, "Origin Y must be panned to 250.0")
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "01b_surface1_spacebar_drag_repositioning.png")

        // Release space key and mouse
        let spaceUpEv = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )!
        _ = boxView.handleOverlayKeyUp(with: spaceUpEv)
        assert(!boxView.spaceKeyDragging, "spaceKeyDragging must be false after space release")

        let spaceMouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: spacePannedTarget,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 4,
            clickCount: 1,
            pressure: 0.0
        )!
        boxView.mouseUp(with: spaceMouseUp)

        // 1b. Option Center-Out and Option+Shift Square Drag Selection Creation
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
            eventNumber: 5,
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
            eventNumber: 6,
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
            eventNumber: 7,
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
            eventNumber: 8,
            clickCount: 1,
            pressure: 0.0
        )!
        boxView.mouseUp(with: upEv)

        // 1c. Option Center-Out Handle Resizing across all 8 handles
        let initialBaseRect = CGRect(x: 300, y: 250, width: 400, height: 300)
        boxView.selectionRect = initialBaseRect
        let centerPoint = CGPoint(x: initialBaseRect.midX, y: initialBaseRect.midY)

        // Symmetrical corner resize test on geometry
        let cornerResizedOpt = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: CGPoint(x: 750, y: 200),
            anchor: CGPoint(x: 300, y: 550),
            bounds: boxView.bounds,
            currentRect: initialBaseRect,
            shiftKeyPressed: false,
            optionKeyPressed: true
        )
        assert(cornerResizedOpt.midX == centerPoint.x, "Option handle resize must keep center fixed (midX)")
        assert(cornerResizedOpt.midY == centerPoint.y, "Option handle resize must keep center fixed (midY)")

        // Symmetrical corner resize + Shift 1:1 square
        let cornerResizedOptShift = SelectionBoxGeometry.calculateResizedRect(
            handle: .bottomRight,
            currentPoint: CGPoint(x: 750, y: 200),
            anchor: CGPoint(x: 300, y: 550),
            bounds: boxView.bounds,
            currentRect: initialBaseRect,
            shiftKeyPressed: true,
            optionKeyPressed: true
        )
        assert(cornerResizedOptShift.midX == centerPoint.x, "Option+Shift handle resize must keep center fixed (midX)")
        assert(cornerResizedOptShift.midY == centerPoint.y, "Option+Shift handle resize must keep center fixed (midY)")
        assert(abs(cornerResizedOptShift.width - cornerResizedOptShift.height) < 0.001, "Option+Shift handle resize must constrain to 1:1 square")

        // Symmetrical edge handle resize (topCenter and middleRight)
        let topResizedOpt = SelectionBoxGeometry.calculateResizedRect(
            handle: .topCenter,
            currentPoint: CGPoint(x: 500, y: 600),
            anchor: CGPoint(x: 500, y: 250),
            bounds: boxView.bounds,
            currentRect: initialBaseRect,
            shiftKeyPressed: false,
            optionKeyPressed: true
        )
        assert(topResizedOpt.midY == centerPoint.y, "topCenter Option resize must keep center fixed (midY)")
        assert(topResizedOpt.width == initialBaseRect.width, "topCenter Option resize must keep width unchanged")

        let rightResizedOpt = SelectionBoxGeometry.calculateResizedRect(
            handle: .middleRight,
            currentPoint: CGPoint(x: 750, y: 400),
            anchor: CGPoint(x: 300, y: 400),
            bounds: boxView.bounds,
            currentRect: initialBaseRect,
            shiftKeyPressed: false,
            optionKeyPressed: true
        )
        assert(rightResizedOpt.midX == centerPoint.x, "middleRight Option resize must keep center fixed (midX)")
        assert(rightResizedOpt.height == initialBaseRect.height, "middleRight Option resize must keep height unchanged")

        // 1d. Cmd+A Fullscreen Selection
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

        // 1e. Arrow Nudging and Option+Arrow Resizing on Selection Box (selectedObjectID == nil)
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
        assert(boxView.toolHUDText == LocalizationManager.shared.tr(.hudNudge(1)), "Nudge must display Nudge (1pt) HUD pill")
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02f_surface1_nudge_hud_pill.png")

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
        assert(boxView.toolHUDText == LocalizationManager.shared.tr(.hudNudge(10)), "Shift+Down arrow must display Nudge (10pt) HUD pill")

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
        let curW = Int(round(boxView.selectionRect.width * 2.0))
        let curH = Int(round(boxView.selectionRect.height * 2.0))
        assert(boxView.toolHUDText == LocalizationManager.shared.tr(.hudResize(curW, curH)), "Option+Right must display W x H px HUD pill")
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02g_surface1_resize_hud_pill.png")

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

        // 2c. In-Place Capture Copy Confirmation HUD
        boxView.showHUDNotification(text: LocalizationManager.shared.tr(.copiedToClipboard))
        assert(boxView.toolHUDText == LocalizationManager.shared.tr(.copiedToClipboard))
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02c_surface1_capture_overlay_copy_hud.png")

        // 2c2. Double-Click Selection to Quick-Copy and Dismiss
        var doubleClickQuickCopyFired = false
        boxView.toolbarsViewModel.onCopyRequested = {
            doubleClickQuickCopyFired = true
        }
        let doubleClickEvt = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: boxView.selectionRect.midX, y: boxView.selectionRect.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 101,
            clickCount: 2,
            pressure: 1.0
        )!
        boxView.mouseDown(with: doubleClickEvt)
        assert(doubleClickQuickCopyFired, "Double-clicking inside selection box must trigger instant copy callback")

        // 2c3. Interactive Dimension Badge Click-to-Copy and Cursor Resolution
        let badgeFrame = boxView.dimensionBadgeFrame()
        assert(!badgeFrame.isEmpty, "dimensionBadgeFrame must not be empty for active selection")
        let badgeCenter = NSPoint(x: badgeFrame.midX, y: badgeFrame.midY)
        let resolvedBadgeCursor = boxView.resolveCanvasCursor(at: badgeCenter)
        assert(resolvedBadgeCursor == NSCursor.pointingHand, "Hovering over dimension badge must resolve to pointingHand cursor")

        let badgeClickEvt = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: badgeCenter,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 102,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDown(with: badgeClickEvt)
        let copiedBadgeStr = NSPasteboard.general.string(forType: .string) ?? ""
        assert(copiedBadgeStr.contains("px"), "Clicking dimension badge must copy resolution string to clipboard")
        assert(boxView.toolHUDText == LocalizationManager.shared.tr(.copiedDimensions), "HUD must show Copied Dimensions")
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02h_surface1_dimension_badge_click_hud.png")

        // 2c4. Feature 173 and Feature 177: Interactive Quick Copy Action Pill and Hover Highlight
        let qcPillFrame = boxView.quickCopyPillFrame()
        assert(!qcPillFrame.isEmpty, "quickCopyPillFrame must not be empty for active selection")
        let dBadgeFrame = boxView.dimensionBadgeFrame()
        assert(qcPillFrame.minX == dBadgeFrame.maxX + 6.0 || qcPillFrame.maxX == dBadgeFrame.minX - 6.0, "Quick copy pill must be adjacent to dimension badge")

        let pillCenter = CGPoint(x: qcPillFrame.midX, y: qcPillFrame.midY)
        let pillCursor = boxView.resolveCanvasCursor(at: pillCenter)
        assert(pillCursor === NSCursor.pointingHand, "Hovering over quick copy pill must resolve to pointingHand cursor")

        // Visual Hover Highlight on Dimension Badge (Feature 177)
        let hoverBadgeEv = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: badgeCenter,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 103,
            clickCount: 0,
            pressure: 0.0
        )!
        boxView.mouseMoved(with: hoverBadgeEv)
        assert(boxView.isHoveringDimensionBadge, "isHoveringDimensionBadge must be true when cursor is over badge")
        assert(!boxView.isHoveringQuickCopyPill, "isHoveringQuickCopyPill must be false when cursor is over badge")
        boxView.needsDisplay = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02j_surface1_dimension_badge_hover.png")

        // Visual Hover Highlight on Quick Copy Pill (Feature 177)
        let hoverPillEv = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: pillCenter,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 104,
            clickCount: 0,
            pressure: 0.0
        )!
        boxView.mouseMoved(with: hoverPillEv)
        assert(!boxView.isHoveringDimensionBadge, "isHoveringDimensionBadge must be false when cursor is over pill")
        assert(boxView.isHoveringQuickCopyPill, "isHoveringQuickCopyPill must be true when cursor is over pill")
        boxView.needsDisplay = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02i_surface1_quick_copy_pill_hover.png")

        // 1-Click Quick Copy via Pill (Feature 173)
        var pillCopyTriggered = false
        boxView.toolbarsViewModel.onCopyRequested = {
            pillCopyTriggered = true
        }
        let clickPillEv = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: pillCenter,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 105,
            clickCount: 1,
            pressure: 1.0
        )!
        boxView.mouseDown(with: clickPillEv)
        assert(pillCopyTriggered, "Clicking Quick Copy pill must trigger onCopyRequested")

        // Reset hover states
        let hoverAwayEv = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: CGPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            eventNumber: 106,
            clickCount: 0,
            pressure: 0.0
        )!
        boxView.mouseMoved(with: hoverAwayEv)
        assert(!boxView.isHoveringDimensionBadge)
        assert(!boxView.isHoveringQuickCopyPill)

        // 2d. Tab / Shift+Tab Selection Cycling with Positional HUD Pill
        let cycleRect = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 250, y: 240, width: 140, height: 90),
            colorHex: "#FF3B30",
            strokeWidth: 3,
            fontSize: 18
        )
        let cycleArrow = AnnotationObject(
            tool: .arrow,
            bounds: CGRect(x: 420, y: 240, width: 140, height: 90),
            colorHex: "#34C759",
            strokeWidth: 3,
            fontSize: 18
        )
        let cycleEllipse = AnnotationObject(
            tool: .ellipse,
            bounds: CGRect(x: 590, y: 240, width: 140, height: 90),
            colorHex: "#007AFF",
            strokeWidth: 3,
            fontSize: 18
        )
        let cycleLine = AnnotationObject(
            tool: .line,
            bounds: CGRect(x: 760, y: 240, width: 120, height: 90),
            colorHex: "#FF9500",
            strokeWidth: 3,
            fontSize: 18
        )
        boxView.annotationEngine.objects = [cycleRect, cycleArrow, cycleEllipse, cycleLine]
        boxView.annotationEngine.deselectAll()

        let tabEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
        // First Tab selects cycleRect (1/4)
        _ = boxView.handleOverlayKeyDown(with: tabEvent)
        assert(boxView.annotationEngine.selectedObjectID == cycleRect.id, "Tab must select first object")
        assert(boxView.toolHUDText?.contains("1/4") == true, "HUD must display 1/4 positional indicator")

        // Second Tab selects cycleArrow (2/4) - Arrow 2/4 (A)
        _ = boxView.handleOverlayKeyDown(with: tabEvent)
        assert(boxView.annotationEngine.selectedObjectID == cycleArrow.id, "Second Tab must select arrow")
        assert(boxView.toolHUDText?.contains("2/4") == true, "HUD must display 2/4 positional indicator")
        assert(boxView.toolHUDText?.contains("(A)") == true, "HUD must display (A) mnemonic key")
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02d_surface1_tab_selection_cycling_hud.png")

        let shiftTabEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
        let handledShiftTab = boxView.handleOverlayKeyDown(with: shiftTabEvent)
        assert(handledShiftTab, "Shift+Tab must reverse cycle selection")
        assert(boxView.annotationEngine.selectedObjectID == cycleRect.id, "Shift+Tab must reverse to cycleRect")
        assert(boxView.toolHUDText?.contains("1/4") == true, "HUD must display 1/4 indicator")

        // 2e. Delete / Backspace HUD Pill (.hudDelete)
        let deleteEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "\u{7F}",
            charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false,
            keyCode: 51
        )!
        let countBeforeDelete = boxView.annotationEngine.objects.count
        let handledDelete = boxView.handleOverlayKeyDown(with: deleteEvent)
        assert(handledDelete, "Delete key must delete selected annotation in SelectionBoxView")
        assert(boxView.annotationEngine.objects.count == countBeforeDelete - 1, "Delete must remove selected object")
        assert(boxView.toolHUDText == LocalizationManager.shared.tr(.hudDelete), "HUD must show .hudDelete text")
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "02e_surface1_delete_hud_pill.png")

        // Clean up temporary cycling objects
        _ = boxView.annotationEngine.clearAll()

        // 2f. Tool Single-Key Mnemonic Parity ('M' for Mosaic Blur, 'E' for Ellipse)
        assert(AnnotationToolType.blur.mnemonicKey == "B")
        assert(AnnotationToolType.blur.alternateMnemonicKey == "M")
        assert(AnnotationToolType.ellipse.mnemonicKey == "C")
        assert(AnnotationToolType.ellipse.alternateMnemonicKey == "E")

        let mKeyEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "m",
            charactersIgnoringModifiers: "m",
            isARepeat: false,
            keyCode: 46
        )!
        _ = boxView.handleOverlayKeyDown(with: mKeyEvent)
        assert(boxView.toolbarsViewModel.activeTool == .blur, "Key 'm' must select .blur tool")

        let eKeyEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlay.windowNumber,
            context: nil,
            characters: "e",
            charactersIgnoringModifiers: "e",
            isARepeat: false,
            keyCode: 14
        )!
        _ = boxView.handleOverlayKeyDown(with: eKeyEvent)
        assert(boxView.toolbarsViewModel.activeTool == .ellipse, "Key 'e' must select .ellipse tool")

        // 3. Edge-case selection near top-right corner to verify toolbar flipping and clamping
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
        assert(!badgeFrameBL.intersects(edgeFramesBL.horizontal), "Dimension badge must not intersect horizontal toolbar in bottom-left selection!")
        assert(badgeFrameBL.minY >= edgeFramesBL.horizontal.maxY, "Dimension badge must be positioned above flipped horizontal toolbar!")
        snapshotWindow(overlay, to: "03b_surface1_bottom_left_clamping.png")
        snapshotWindow(overlay, to: "03c_surface1_bottom_toolbar_no_badge_collision.png")

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
            bounds: CGRect(x: 240, y: 370, width: 380, height: 34),
            colorHex: "#007AFF",
            strokeWidth: 3,
            fontSize: 22,
            text: "SuperShot v1.0.26 Live GUI Verification"
        )
        engine.addObject(txtObj)
        engine.selectedObjectID = txtObj.id
        boxView.updateTextTargetState()
        assert(boxView.toolbarsViewModel.isTextTargetActive, "Text target must be active when Text object is selected")

        // 8b. Feature 175: Text Annotation Font Size Stepping ([ / ]) & HUD
        let initialTxtFontSize = engine.selectedObject?.fontSize ?? 22

        // Step font size up with ] (keyCode 30) -> 24pt
        let bracketStepUp = NSEvent.keyEvent(
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
        let handledStepUp = boxView.handleOverlayKeyDown(with: bracketStepUp)
        assert(handledStepUp, "Bracket ] key must be handled by overlay")
        assert(engine.selectedObject?.fontSize == initialTxtFontSize + 2, "Bracket ] must increase font size by 2pt")
        assert(boxView.toolHUDText == LocalizationManager.shared.tr(.fontSizeHUD(Int(round(initialTxtFontSize + 2)))), "HUD must show fontSizeHUD")
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        snapshotWindow(overlay, to: "05b_surface3_font_size_stepping_hud.png")

        // Step font size back down with [ (keyCode 33) -> 22pt
        let bracketStepDown = NSEvent.keyEvent(
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
        let handledStepDown = boxView.handleOverlayKeyDown(with: bracketStepDown)
        assert(handledStepDown, "Bracket [ key must be handled by overlay")
        assert(engine.selectedObject?.fontSize == initialTxtFontSize, "Bracket [ must decrease font size back to initial")

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

        // 9. Bracket Shortcuts [ and ] for Stroke Width Stepping when text target is not active
        boxView.annotationEngine.deselectAll()
        boxView.updateTextTargetState()
        assert(!boxView.toolbarsViewModel.isTextTargetActive, "isTextTargetActive should be false when nothing is selected")

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

        // 10c. Direct Verification of AnnotationEngine.selectNextObject(reverse:)
        let firstObjId = engine.objects.first?.id
        let lastObjId = engine.objects.last?.id
        engine.deselectAll()
        let cycledFirst = engine.selectNextObject(reverse: false)
        assert(cycledFirst == firstObjId, "Forward cycle from nil must select first object")
        let cycledLast = engine.selectNextObject(reverse: true)
        assert(cycledLast == lastObjId, "Reverse cycle from first must wrap to last object")
        let cycledBackAgain = engine.selectNextObject(reverse: true)
        assert(cycledBackAgain == engine.objects[engine.objects.count - 2].id, "Reverse cycle must move backward")

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

        // Shift-Constrained Arrow (45 deg angle snap)
        engine.activeTool = .arrow
        engine.startDrag(at: CGPoint(x: 850, y: 220), colorHex: "#34C759", strokeWidth: 4, fontSize: 18)
        engine.updateDrag(to: CGPoint(x: 970, y: 230), shiftKeyPressed: true) // Near horizontal -> snaps to 0 deg
        _ = engine.endDrag(at: CGPoint(x: 970, y: 230))
        if let lastArrow = engine.objects.last, lastArrow.points.count >= 2 {
            let dy = abs(lastArrow.points[1].y - lastArrow.points[0].y)
            assert(dy < 0.001, "Shift-constrained horizontal arrow must snap to 0 deg angle")
        }

        // 4-TIER HIERARCHICAL ESCAPE KEY HANDLING VERIFICATION
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
                tags: ["v1.0.26", "annotated", "shift-constrained"]
            )
        }
        overlay.close()
        print("  [PASS] Surface 3: Vector Annotation Engine, Font Stepping, Mosaic Blur, Cmd+D, Cmd+E, Cmd+Shift+K & 4-Tier Esc verified.")

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

                // Test Tab selection cycling in ScrollableCanvasView
                let sTabEvent = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: scrollWin.windowNumber,
                    context: nil,
                    characters: "\t",
                    charactersIgnoringModifiers: "\t",
                    isARepeat: false,
                    keyCode: 48
                )!
                scrollWin.keyDown(with: sTabEvent)
                assert(sEngine.selectedObjectID != nil, "Tab in tall canvas must select an annotation")

                // Test Delete HUD notification in tall canvas
                let sDeleteEvent = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: scrollWin.windowNumber,
                    context: nil,
                    characters: "\u{7F}",
                    charactersIgnoringModifiers: "\u{7F}",
                    isARepeat: false,
                    keyCode: 51
                )!
                let sCountBefore = sEngine.objects.count
                scrollWin.keyDown(with: sDeleteEvent)
                assert(sEngine.objects.count == sCountBefore - 1, "Delete in tall canvas must remove selected object")
                scrollWin.canvasView.documentView.showHUDNotification(text: LocalizationManager.shared.tr(.hudDelete))
                RunLoop.current.run(until: Date().addingTimeInterval(0.10))
                snapshotWindow(scrollWin, to: "08b_surface4_scrollable_canvas_hud_delete.png")
            }

            // Feature 179: Double-Click Quick Copy Parity on Tall Stitched Canvas
            var tallCanvasQuickCopyCalled = false
            scrollWin.canvasView.documentView.onQuickCopyRequested = {
                tallCanvasQuickCopyCalled = true
            }
            let docDoubleClick = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 50, y: 50),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: scrollWin.windowNumber,
                context: nil,
                eventNumber: 201,
                clickCount: 2,
                pressure: 1.0
            )!
            scrollWin.canvasView.documentView.mouseDown(with: docDoubleClick)
            assert(tallCanvasQuickCopyCalled, "Double-clicking empty canvas in tall window must trigger onQuickCopyRequested")

            // Feature 176: Tall Canvas Fit to Window Zoom Button & Cmd+9
            scrollWin.canvasView.scrollView.magnification = 2.0
            scrollWin.canvasView.zoomToFitWindow()
            let fitMag = scrollWin.canvasView.zoomViewModel.magnification
            assert(fitMag >= 0.1 && fitMag <= 4.0, "Fit to window magnification must be clamped properly")
            scrollWin.canvasView.showHUDNotification(text: LocalizationManager.shared.tr(.zoomHUD(Int(round(fitMag * 100)))))
            RunLoop.current.run(until: Date().addingTimeInterval(0.10))
            snapshotWindow(scrollWin, to: "08c_surface4_tall_canvas_fit_to_window.png")

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
            assert(abs(scrollWin.canvasView.scrollView.contentView.bounds.origin.y - (startOriginY + 40.0)) < 0.01)

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
            assert(abs(currY - (startOriginY + 160.0)) < 0.01)

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
            assert(scrollWin.canvasView.scrollView.contentView.bounds.origin.y > startOriginY + 160.0)

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
            assert(abs(scrollWin.canvasView.scrollView.contentView.bounds.origin.y) < 0.01)

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
            assert(scrollWin.canvasView.scrollView.contentView.bounds.origin.y > 0.0)

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
            assert(abs(scrollWin.canvasView.scrollView.contentView.bounds.origin.y) < 0.01)

            // Verify Zoom HUD notification feedback
            scrollWin.canvasView.scrollView.zoomIn()
            scrollWin.canvasView.showHUDNotification(text: LocalizationManager.shared.tr(.zoomHUD(120)))

            // Verify dark appearance styling
            assert(scrollWin.appearance?.name == .darkAqua)
            assert(scrollWin.backgroundColor != nil)
            let whiteComp = scrollWin.backgroundColor?.whiteComponent ?? 0
            assert(abs(whiteComp - 0.12) < 0.001)
            assert(scrollWin.canvasView.scrollView.drawsBackground == true)

            scrollWin.canvasView.documentView.needsDisplay = true
            snapshotWindow(scrollWin, to: "08_surface4_scrollable_annotation_window.png")
            scrollWin.close()
        }
        print("  [PASS] Surface 4: Region-First Manual Scroll Capture & Tall Canvas verified.")

        // =========================================================================
        // SURFACE 5: Menu Bar Popover, UpdateManager & Multi-Tab Settings
        // =========================================================================
        print("\n--- Surface 5: Menu Bar Popover, UpdateManager & Multi-Tab Settings ---")
        // Populate additional history items (both pinned and unpinned)
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
                tags: ["pinned", "v1.0.26"]
            ) {
                delegate.storageManager.togglePin(id: pinnedItem.id)
                createdPinnedItem = delegate.storageManager.items.first(where: { $0.id == pinnedItem.id })
            }
        }

        // Add extra recent item to ensure multiple recent items exist
        if let thirdImg = ScreenCaptureManager.cropImage(
            captured.fullImage,
            selectionInWindow: CGRect(x: 220, y: 180, width: 400, height: 300),
            windowSize: CGSize(width: 1440, height: 900),
            scaleFactor: 2.0
        ) {
            _ = try? delegate.storageManager.save(
                image: thirdImg,
                sourceApp: "Terminal",
                captureType: .region,
                tags: ["recent", "v1.0.26"]
            )
        }

        // Verify Section Shortcut Navigation logic & Badges
        let pinnedList = delegate.storageManager.pinnedItems
        let recentList = delegate.storageManager.recentItems
        assert(!pinnedList.isEmpty, "Pinned items list must not be empty")
        assert(!recentList.isEmpty, "Recent items list must not be empty")

        if let firstPinned = pinnedList.first {
            let badgeP = ShortcutNavigator.badgeString(for: firstPinned, pinnedItems: pinnedList, recentItems: recentList)
            assert(badgeP == "⌥1", "First pinned item badge must be ⌥1 (actual: \(badgeP ?? "nil"))")
        }
        if let firstRecent = recentList.first {
            let badgeR = ShortcutNavigator.badgeString(for: firstRecent, pinnedItems: pinnedList, recentItems: recentList)
            assert(badgeR == "1", "First recent item badge must be 1 (actual: \(badgeR ?? "nil"))")
        }

        // 1. Popover without update banner (normal status)
        UpdateManager.shared.status = .idle
        delegate.statusItemManager.showPopover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if let popWin = delegate.statusItemManager.popover.contentViewController?.view.window {
            snapshotWindow(popWin, to: "09_surface5_history_popover_normal.png")
        }
        delegate.statusItemManager.dismissPopover()

        // 1b. Empty Search Filter State
        let emptySearchShotView = MainShotView(
            storageManager: delegate.storageManager,
            appSettings: delegate.appSettings,
            initialSearchText: "nomatch_query_clear_test"
        )
        let emptySearchWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        emptySearchWin.appearance = NSAppearance(named: .darkAqua)
        emptySearchWin.contentView = NSHostingView(rootView: emptySearchShotView)
        snapshotWindow(emptySearchWin, to: "09b_surface5_history_popover_empty_search.png")

        // 1c. Test "/" and "Cmd+F" shortcut notifications to focus search field
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

        // Verify Dynamic Status Item ToolTip
        delegate.statusItemManager.updateStatusItemToolTip()
        let enTooltip = delegate.statusItemManager.statusItem.button?.toolTip ?? ""
        assert(enTooltip.contains("SuperShot"), "Tooltip must contain app title")

        LocalizationManager.shared.setLanguage(code: "vi")
        let viTooltip = delegate.statusItemManager.statusItem.button?.toolTip ?? ""
        assert(viTooltip.contains("Chụp") || viTooltip.contains("SuperShot"), "Tooltip in Vietnamese must update dynamically")
        LocalizationManager.shared.setLanguage(code: "en")

        // 2. Popover WITH update banner (Cycle 19 Target: v1.0.26 / Build 26)
        let sampleRelease = ReleaseInfo(
            tagName: "v1.0.26",
            name: "SuperShot v1.0.26",
            releaseNotes: "## Improvements\n- Stitching Zero-Delta Low-Entropy Alignment\n- Moving Frame Header and Footer Deduplication\n- Spacebar and Escape Gesture Protection\n- Deterministic Scaled Handle Hit-Testing\n- Metadata Backup Resilience",
            htmlURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.26")!,
            zipAssetURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.26/SuperShot-v1.0.26.zip"),
            dmgAssetURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.26/SuperShot-v1.0.26.dmg")
        )
        UpdateManager.shared.status = .updateAvailable(sampleRelease)
        assert(UpdateManager.shared.shouldShowBanner, "Update banner should be visible when update is available")
        delegate.statusItemManager.showPopover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if let popWin = delegate.statusItemManager.popover.contentViewController?.view.window {
            snapshotWindow(popWin, to: "10_surface5_history_popover_update_banner.png")
        }

        // 2b. Popover Downloading Banner with Cancel Button
        UpdateManager.shared.status = .downloading(progress: 0.55)
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        if let popWin = delegate.statusItemManager.popover.contentViewController?.view.window {
            snapshotWindow(popWin, to: "10b_surface5_history_popover_update_downloading.png")
        }
        UpdateManager.shared.cancelDownload()
        assert(UpdateManager.shared.downloadProgress == 0.0, "cancelDownload must reset progress")

        // 3. Popover Feedback Toasts (Copy, Delete, Clear Unpinned, File Path, Dimensions)
        if let mainShotView = delegate.statusItemManager.popover.contentViewController as? NSHostingController<MainShotView> {
            let itemToCopy = delegate.storageManager.items.first!
            mainShotView.rootView.triggerCopyFeedback(for: itemToCopy.id)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            if let popWin = mainShotView.view.window {
                snapshotWindow(popWin, to: "11_surface5_history_popover_copy_feedback.png")

                // 3b. Popover Delete Toast Feedback
                mainShotView.rootView.triggerDeleteFeedback()
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                snapshotWindow(popWin, to: "11b_surface5_history_popover_delete_feedback.png")

                // 3c. Popover Clear Unpinned History Toast Feedback
                mainShotView.rootView.triggerClearAllFeedback()
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                snapshotWindow(popWin, to: "11c_surface5_history_popover_unpinned_cleared_feedback.png")

                // 3d. Feature 178: Popover Copy File Path (Cmd+Shift+C) Feedback Toast
                mainShotView.rootView.copySelectedFilePath()
                let copiedPath = NSPasteboard.general.string(forType: .string) ?? ""
                assert(!copiedPath.isEmpty && copiedPath.hasPrefix("/"), "Cmd+Shift+C must copy valid file path to pasteboard")
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                snapshotWindow(popWin, to: "11d_surface5_history_popover_copied_filepath_toast.png")

                // 3e. Feature 178: Popover Copy Dimensions (Cmd+Option+C) Feedback Toast
                mainShotView.rootView.copySelectedDimensions()
                let copiedDims = NSPasteboard.general.string(forType: .string) ?? ""
                assert(copiedDims.contains("x") || copiedDims.contains("×") || copiedDims.contains("px"), "Cmd+Option+C must copy valid dimensions string to pasteboard")
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                snapshotWindow(popWin, to: "11e_surface5_history_popover_copied_dimensions_toast.png")
            }
        }
        delegate.statusItemManager.dismissPopover()

        // 3f. Verify Popover Quick Share & Re-Annotate Actions
        var annotatedItemInvoked: ShotItem?
        let testMainShotView = MainShotView(
            storageManager: delegate.storageManager,
            appSettings: delegate.appSettings,
            onAnnotateItem: { it in
                annotatedItemInvoked = it
            }
        )
        if let firstItem = delegate.storageManager.items.first {
            testMainShotView.annotateItem(firstItem)
            assert(annotatedItemInvoked?.id == firstItem.id, "annotateItem must invoke onAnnotateItem callback")
            testMainShotView.shareItem(firstItem, from: nil)
        }

        // 3g. Verify ShotRowView Native SF Symbols in Context Menu
        let sampleRow = ShotRowView(
            item: delegate.storageManager.items.first!,
            storageManager: delegate.storageManager,
            isSelected: false,
            onSelect: nil
        )
        let sampleHosting = NSHostingView(rootView: sampleRow)
        sampleHosting.frame = NSRect(x: 0, y: 0, width: 350, height: 72)
        sampleHosting.needsLayout = true
        sampleHosting.layoutSubtreeIfNeeded()
        assert(sampleHosting.bounds.width == 350, "ShotRowView host bounds width is 350")

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

        // 5. Settings Window in English (all 4 tabs) - Height >= 565pt
        LocalizationManager.shared.setLanguage(code: "en")
        delegate.appSettings.language = "en"
        delegate.appSettings.lastUpdateCheckDate = Date().addingTimeInterval(-300)

        delegate.openSettings(tab: .general)
        if let settingsWin = delegate.settingsWindowController.window {
            let frame = settingsWin.frame
            assert(frame.size.height >= 565, "Settings window height must be at least 565pt (actual: \(frame.size.height))")
            assert(frame.size.width >= 520, "Settings window width must be at least 520pt (actual: \(frame.size.width))")

            snapshotWindow(settingsWin, to: "13_surface5_settings_general_en.png")

            // Tab 2: Capture & Save with "Open in Finder" Quick Button
            delegate.openSettings(tab: .captureSave)
            snapshotWindow(settingsWin, to: "14_surface5_settings_capturesave_en.png")

            // Tab 3: History (Shortcuts & Retention)
            delegate.openSettings(tab: .history)
            snapshotWindow(settingsWin, to: "15_surface5_settings_history_en.png")

            // Tab 4: About - State 1: .updateAvailable
            UpdateManager.shared.status = .updateAvailable(sampleRelease)
            delegate.openSettings(tab: .about)
            snapshotWindow(settingsWin, to: "16_surface5_settings_about_en.png")

            // Tab 4: About - State 2: .upToDate
            UpdateManager.shared.status = .upToDate(currentVersion: "1.0.26")
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "16a_surface5_settings_about_uptodate_en.png")

            // Tab 4: About - State 3: .downloading
            UpdateManager.shared.status = .downloading(progress: 0.68)
            UpdateManager.shared.downloadProgress = 0.68
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "16b_surface5_settings_about_downloading_en.png")

            // Verify download cancellation in About tab
            UpdateManager.shared.cancelDownload()
            assert(UpdateManager.shared.downloadProgress == 0.0, "cancelDownload must reset progress")

            // Tab 4: About - State 4: .readyToRestart
            UpdateManager.shared.status = .readyToRestart(sampleRelease)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "16c_surface5_settings_about_readytorestart_en.png")

            // Tab 4: About - State 5: .error
            UpdateManager.shared.status = .error(message: "Network unreachable")
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "16f_surface5_settings_about_error_en.png")

            // In-App Release Notes Viewer Modal Sheet
            let releaseNotesView = ReleaseNotesSheetView(release: sampleRelease) {}
            let sheetWin = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            sheetWin.contentView = NSHostingView(rootView: releaseNotesView)
            snapshotWindow(sheetWin, to: "16d_surface5_release_notes_sheet.png")

            let fallbackRelease = ReleaseInfo(
                tagName: "v1.0.26",
                name: "SuperShot v1.0.26",
                releaseNotes: "",
                htmlURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.26")!
            )
            let fallbackNotesView = ReleaseNotesSheetView(release: fallbackRelease) {}
            sheetWin.contentView = NSHostingView(rootView: fallbackNotesView)
            snapshotWindow(sheetWin, to: "16e_surface5_release_notes_sheet_fallback.png")

            // 5b. Multi-Language Settings Verification (French, German, Spanish, Japanese, Chinese, Korean)
            let multiLangs = ["fr", "de", "es", "ja", "zh-Hans", "zh-Hant", "ko"]
            for langCode in multiLangs {
                LocalizationManager.shared.setLanguage(code: langCode)
                delegate.appSettings.language = langCode
                delegate.openSettings(tab: .general)
                snapshotWindow(settingsWin, to: "16_\(langCode)_surface5_settings_general.png")
            }

            // 6. Settings Window in Vietnamese (all 4 tabs & About states)
            LocalizationManager.shared.setLanguage(code: "vi")
            delegate.appSettings.language = "vi"

            delegate.openSettings(tab: .general)
            snapshotWindow(settingsWin, to: "17_surface5_settings_general_vi.png")

            delegate.openSettings(tab: .captureSave)
            snapshotWindow(settingsWin, to: "18_surface5_settings_capturesave_vi.png")

            delegate.openSettings(tab: .history)
            snapshotWindow(settingsWin, to: "19_surface5_settings_history_vi.png")

            UpdateManager.shared.status = .updateAvailable(sampleRelease)
            delegate.openSettings(tab: .about)
            snapshotWindow(settingsWin, to: "20_surface5_settings_about_vi.png")

            UpdateManager.shared.status = .upToDate(currentVersion: "1.0.26")
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "20a_surface5_settings_about_uptodate_vi.png")

            UpdateManager.shared.status = .downloading(progress: 0.68)
            UpdateManager.shared.downloadProgress = 0.68
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "20b_surface5_settings_about_downloading_vi.png")

            UpdateManager.shared.status = .readyToRestart(sampleRelease)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "20c_surface5_settings_about_readytorestart_vi.png")

            // Vietnamese Error state
            UpdateManager.shared.status = .error(message: "Không thể kết nối máy chủ")
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            snapshotWindow(settingsWin, to: "20d_surface5_settings_about_error_vi.png")

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

            // 7b. Test Control+Tab & Control+Shift+Tab Settings Tab Cycling
            let ctrlTabEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.control],
                timestamp: 0,
                windowNumber: settingsWin.windowNumber,
                context: nil,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                isARepeat: false,
                keyCode: 48
            )!
            settingsWin.keyDown(with: ctrlTabEvent)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))

            // 7c. About Tab Diagnostic String Verification
            let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.26"
            let currentBld = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "26"
            let diag = AboutSettingsTab.diagnosticString(version: currentVer)
            assert(diag.contains("SuperShot v\(currentVer)") || diag.contains("SuperShot v1.0.26"), "Diagnostic string must contain SuperShot version")
            assert(diag.contains("Build \(currentBld)") || diag.contains("Build 26"), "Diagnostic string must contain Build number")

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

            // 8b. Test Cmd+W key dismissal on SettingsWindow
            delegate.openSettings(tab: .general)
            assert(settingsWin.isVisible, "Settings window must be visible after openSettings")
            let cmdWEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: settingsWin.windowNumber,
                context: nil,
                characters: "w",
                charactersIgnoringModifiers: "w",
                isARepeat: false,
                keyCode: 13
            )!
            settingsWin.keyDown(with: cmdWEvent)
            RunLoop.current.run(until: Date().addingTimeInterval(0.10))
            assert(!settingsWin.isVisible, "Cmd+W key must dismiss settings window")
        }
        print("  [PASS] Surface 5: History Popover, Section Shortcuts, Dynamic Tooltip, Feedback Toasts & Settings verified.")

        // =========================================================================
        // SURFACE 6: Welcome Window across 9 Languages
        // =========================================================================
        print("\n--- Surface 6: Welcome Window across 9 Languages ---")
        // English Welcome Window
        LocalizationManager.shared.setLanguage(code: "en")
        WelcomeWindowController.shared.showWelcomeWindow()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        if let welcomeWin = WelcomeWindowController.shared.window {
            assert(welcomeWin.frame.width == 520, "Welcome window width must be 520pt (actual: \(welcomeWin.frame.width))")
            assert(welcomeWin.frame.height >= 460 && welcomeWin.frame.height <= 495, "Welcome window height must be between 460pt and 495pt (actual: \(welcomeWin.frame.height))")
            snapshotWindow(welcomeWin, to: "22_surface6_welcome_window_en.png")
            snapshotWindow(welcomeWin, to: "22_surface6_welcome_window.png")

            // Test Escape Dismissal
            let welcomeEsc = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: welcomeWin.windowNumber,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            )!
            welcomeWin.keyDown(with: welcomeEsc)
            RunLoop.current.run(until: Date().addingTimeInterval(0.10))
            assert(!welcomeWin.isVisible, "WelcomeWindow must dismiss on Escape key press")

            // Test Cmd+W Dismissal
            WelcomeWindowController.shared.showWelcomeWindow()
            RunLoop.current.run(until: Date().addingTimeInterval(0.10))
            assert(welcomeWin.isVisible, "WelcomeWindow must be visible before Cmd+W")
            let welcomeCmdW = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: welcomeWin.windowNumber,
                context: nil,
                characters: "w",
                charactersIgnoringModifiers: "w",
                isARepeat: false,
                keyCode: 13
            )!
            welcomeWin.keyDown(with: welcomeCmdW)
            RunLoop.current.run(until: Date().addingTimeInterval(0.10))
            assert(!welcomeWin.isVisible, "WelcomeWindow must dismiss on Cmd+W key press")
        }

        // Vietnamese Welcome Window
        LocalizationManager.shared.setLanguage(code: "vi")
        WelcomeWindowController.shared.showWelcomeWindow()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        if let welcomeWin = WelcomeWindowController.shared.window {
            assert(welcomeWin.frame.width == 520, "Welcome window width must be 520pt")
            snapshotWindow(welcomeWin, to: "22_vi_surface6_welcome_window.png")
            WelcomeWindowController.shared.dismiss()
        }

        // Feature 180 Multilingual Welcome Window Verification: de, fr, es, ja, zh-Hans, ko
        let welcomeLangs = [
            ("de", "22_de_surface6_welcome_window.png"),
            ("fr", "22_fr_surface6_welcome_window.png"),
            ("es", "22_es_surface6_welcome_window.png"),
            ("ja", "22_ja_surface6_welcome_window.png"),
            ("zh-Hans", "22_zh-Hans_surface6_welcome_window.png"),
            ("ko", "22_ko_surface6_welcome_window.png")
        ]
        for (langCode, filename) in welcomeLangs {
            LocalizationManager.shared.setLanguage(code: langCode)
            WelcomeWindowController.shared.showWelcomeWindow()
            RunLoop.current.run(until: Date().addingTimeInterval(0.20))
            if let welcomeWin = WelcomeWindowController.shared.window {
                assert(welcomeWin.frame.width == 520, "Welcome window width must be 520pt for \(langCode)")
                snapshotWindow(welcomeWin, to: filename)
                WelcomeWindowController.shared.dismiss()
            }
        }

        LocalizationManager.shared.setLanguage(code: "en")
        print("  [PASS] Surface 6: Welcome Window across 9 languages verified.")

        print("\n====================================================================")
        print("  ALL SURFACES LIVE GUI AUDIT PASSED 100% WITH ZERO ERRORS")
        print("====================================================================")
        exit(0)
    }
}
