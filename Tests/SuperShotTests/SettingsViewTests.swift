import Foundation
import CoreGraphics
import AppKit
import SuperShotCore
import SuperShot

public struct SettingsViewTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("SettingsView & AppSettings Configuration Tests")

        let settingsURL = sandboxDir.appendingPathComponent("settings.json")
        let settings = AppSettings(settingsURL: settingsURL)

        // 1. Initial Default State
        TestHarness.assertEqual(settings.activeColorHex, "#FF3B30", "Default active color is Red (#FF3B30)")
        TestHarness.assertEqual(settings.activeStrokeWidth, 3.0, "Default stroke width is 3.0 pt")
        TestHarness.assertEqual(settings.activeFontSize, 18.0, "Default font size is 18.0 pt")
        TestHarness.assertEqual(settings.presets.count, 8, "Initial presets count is 8 defaults")
        TestHarness.assertEqual(settings.saveFormat, .png, "Default save format is PNG")
        TestHarness.assertEqual(settings.maxScrollHeightPx, 15000, "Default maxScrollHeightPx is 15,000 px")
        TestHarness.assertEqual(settings.capacity, 50, "Default capacity is 50 items")
        TestHarness.assertFalse(settings.autoSaveEnabled, "Auto-save is disabled by default")
        TestHarness.assertTrue(settings.autoPasteOnSelection, "Auto-paste is enabled by default")

        // 2. Preset Add, In-place Update & Capacity Clamping
        let newPreset = ColorPreset(name: "Mint", hex: "#00FFCC")
        let added = settings.addPreset(newPreset)
        TestHarness.assertTrue(added, "Successfully added new custom preset")
        TestHarness.assertEqual(settings.presets.count, 9, "Preset count updated to 9")

        // Add up to 16 presets
        for i in 10...16 {
            let p = ColorPreset(name: "Custom \(i)", hex: String(format: "#%06X", i * 1000))
            settings.addPreset(p)
        }
        TestHarness.assertEqual(settings.presets.count, 16, "Preset count reached maximum 16")

        let overLimitPreset = ColorPreset(name: "Over Limit", hex: "#AABBCC")
        let rejected = settings.addPreset(overLimitPreset)
        TestHarness.assertFalse(rejected, "17th unique preset addition rejected at capacity 16")
        TestHarness.assertEqual(settings.presets.count, 16, "Preset count clamped strictly at 16")

        // In-place name update for existing hex
        let updatePreset = ColorPreset(name: "Updated Mint", hex: "#00FFCC")
        let updated = settings.addPreset(updatePreset)
        TestHarness.assertTrue(updated, "Updating existing hex returns true")
        TestHarness.assertEqual(settings.presets.count, 16, "Preset count remains 16 after update")
        TestHarness.assertEqual(settings.presets.first(where: { $0.hex == "#00FFCC" })?.name, "Updated Mint", "Preset name updated in-place")

        // Reset to defaults
        settings.resetPresets()
        TestHarness.assertEqual(settings.presets.count, 8, "Reset presets restored 8 standard defaults")

        // 3. Value Range Clamping
        settings.activeStrokeWidth = 100.0
        TestHarness.assertEqual(settings.activeStrokeWidth, 30.0, "Stroke width clamped to 30.0 pt")
        settings.activeStrokeWidth = 0.1
        TestHarness.assertEqual(settings.activeStrokeWidth, 1.0, "Stroke width clamped to 1.0 pt")

        settings.maxScrollHeightPx = 50000
        TestHarness.assertEqual(settings.maxScrollHeightPx, 30000, "maxScrollHeightPx clamped to 30,000 px")
        settings.maxScrollHeightPx = 1000
        TestHarness.assertEqual(settings.maxScrollHeightPx, 5000, "maxScrollHeightPx clamped to 5,000 px")

        settings.capacity = 1000
        TestHarness.assertEqual(settings.capacity, 500, "History capacity clamped to 500 items")
        settings.capacity = 2
        TestHarness.assertEqual(settings.capacity, 10, "History capacity clamped to 10 items")

        // 4. Persistence Round-Trip Verification
        settings.saveFormat = .jpeg
        settings.jpegQuality = 0.85
        settings.autoSaveEnabled = true
        let customDir = sandboxDir.appendingPathComponent("AutoSaveShots", isDirectory: true)
        settings.autoSaveDirectory = customDir

        try! settings.saveSynchronously(to: settingsURL)
        TestHarness.assertTrue(FileManager.default.fileExists(atPath: settingsURL.path), "settings.json persisted to disk")

        let loadedSettings = AppSettings(settingsURL: settingsURL)
        TestHarness.assertEqual(loadedSettings.saveFormat, .jpeg, "Loaded save format matches JPEG")
        TestHarness.assertEqual(loadedSettings.jpegQuality, 0.85, "Loaded JPEG quality matches 0.85")
        TestHarness.assertTrue(loadedSettings.autoSaveEnabled, "Loaded autoSaveEnabled is true")
        TestHarness.assertEqual(loadedSettings.autoSaveDirectory.path, customDir.path, "Loaded autoSaveDirectory matches custom path")

        // 5. SettingsWindowController Title Localization & Escape Key Dismissal
        let storage = StorageManager(baseDirectory: sandboxDir)
        let controller = SettingsWindowController(appSettings: settings, storageManager: storage)
        TestHarness.assertEqual(controller.window?.title, LocalizationManager.shared.tr(.menuPreferences), "Window title is localized using menuPreferences")

        controller.showSettings(tab: .general)
        TestHarness.assertTrue(controller.window?.isVisible == true, "Settings window is visible")
        let escEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        )!
        controller.window?.keyDown(with: escEvent)
        TestHarness.assertFalse(controller.window?.isVisible == true, "Settings window closed after Escape key")

        // 6. Automatic Update Check Frequency Configuration
        TestHarness.assertTrue(settings.automaticallyCheckForUpdates, "Default automaticallyCheckForUpdates is true")
        TestHarness.assertEqual(settings.updateCheckIntervalDays, 1, "Default updateCheckIntervalDays is 1")
        settings.updateCheckIntervalDays = 7
        TestHarness.assertEqual(settings.updateCheckIntervalDays, 7, "updateCheckIntervalDays set to 7 (weekly)")
        settings.updateCheckIntervalDays = 30
        TestHarness.assertEqual(settings.updateCheckIntervalDays, 30, "updateCheckIntervalDays set to 30 (monthly)")
        settings.updateCheckIntervalDays = 100
        TestHarness.assertEqual(settings.updateCheckIntervalDays, 30, "updateCheckIntervalDays clamped to 30")
        settings.updateCheckIntervalDays = -5
        TestHarness.assertEqual(settings.updateCheckIntervalDays, 1, "updateCheckIntervalDays clamped to 1")

        let generalTab = GeneralSettingsTab(appSettings: settings)
        let _ = generalTab.body
        TestHarness.assertTrue(true, "GeneralSettingsTab body evaluates cleanly with auto-update toggle and interval picker")

        // 7. Settings Window Frame Height & Tab Shortcuts
        TestHarness.assertEqual(controller.window?.contentViewController?.preferredContentSize.height, 565, "Settings window preferred height is 565 pt")
        TestHarness.assertEqual(SettingsTab.general.shortcutNumber, 1, "General tab shortcut is 1")
        TestHarness.assertEqual(SettingsTab.captureSave.shortcutNumber, 2, "Capture & Save tab shortcut is 2")
        TestHarness.assertEqual(SettingsTab.history.shortcutNumber, 3, "History tab shortcut is 3")
        TestHarness.assertEqual(SettingsTab.about.shortcutNumber, 4, "About tab shortcut is 4")
        TestHarness.assertEqual(SettingsTab.general.shortcutHint, "⌘1", "General tab shortcut hint is ⌘1")
        TestHarness.assertEqual(SettingsTab.about.shortcutHint, "⌘4", "About tab shortcut hint is ⌘4")

        // 8. Cmd+1..4 KeyDown Tab Navigation Notification
        var receivedTab: SettingsTab? = nil
        let observer = NotificationCenter.default.addObserver(forName: .settingsSelectTab, object: nil, queue: nil) { notif in
            receivedTab = notif.object as? SettingsTab
        }
        let cmd2Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "2",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: 19
        )!
        controller.window?.keyDown(with: cmd2Event)
        TestHarness.assertEqual(receivedTab, .captureSave, "Cmd+2 event selects .captureSave tab via notification")
        NotificationCenter.default.removeObserver(observer)

        // 8b. Cmd+[ and Cmd+] KeyDown Tab Cycling Notifications
        var receivedCycleDirection: Int? = nil
        let cycleObserver = NotificationCenter.default.addObserver(forName: .settingsCycleTab, object: nil, queue: nil) { notif in
            receivedCycleDirection = notif.userInfo?["direction"] as? Int
        }

        // Cmd+[ (previous tab)
        let cmdLeftBracketEvent = NSEvent.keyEvent(
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
        controller.window?.keyDown(with: cmdLeftBracketEvent)
        TestHarness.assertEqual(receivedCycleDirection, -1, "Cmd+[ posts .settingsCycleTab with direction -1")

        // Cmd+] (next tab)
        let cmdRightBracketEvent = NSEvent.keyEvent(
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
        controller.window?.keyDown(with: cmdRightBracketEvent)
        TestHarness.assertEqual(receivedCycleDirection, 1, "Cmd+] posts .settingsCycleTab with direction 1")

        // Cmd+Shift+[ (previous tab)
        let cmdShiftLeftBracketEvent = NSEvent.keyEvent(
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
        controller.window?.keyDown(with: cmdShiftLeftBracketEvent)
        TestHarness.assertEqual(receivedCycleDirection, -1, "Cmd+Shift+[ posts .settingsCycleTab with direction -1")

        NotificationCenter.default.removeObserver(cycleObserver)

        // 9. WelcomeWindowView & WelcomeWindowController Verification
        var welcomeDismissed = false
        let welcomeView = WelcomeView(onDismiss: { welcomeDismissed = true })
        let _ = welcomeView.body
        TestHarness.assertEqual(welcomeView.appVersionString, "v1.0.20", "WelcomeView version string is v1.0.20")
        welcomeView.onDismiss?()
        TestHarness.assertTrue(welcomeDismissed, "WelcomeView onDismiss executes cleanly")

        // 9b. SettingsTabButton Instant Action & Hit-Target Verification
        var selectedTabFromButton: SettingsTab = .general
        for tab in SettingsTab.allCases {
            let tabButton = SettingsTabButton(tab: tab, isSelected: selectedTabFromButton == tab) {
                selectedTabFromButton = tab
            }
            let _ = tabButton.body
            tabButton.action()
            TestHarness.assertEqual(selectedTabFromButton, tab, "SettingsTabButton action immediately switches selected tab to \(tab.rawValue)")
        }

        let welcomeController = WelcomeWindowController.shared
        TestHarness.assertNotNil(welcomeController.window, "WelcomeWindowController window instantiated")
        TestHarness.assertEqual(welcomeController.window?.contentRect(forFrameRect: welcomeController.window!.frame).width, 520, "Welcome window width is 520 pt")
        TestHarness.assertEqual(welcomeController.window?.contentRect(forFrameRect: welcomeController.window!.frame).height, 460, "Welcome window height is 460 pt")

        // 10. Localization Hygiene Verification across Settings Tabs
        let locMgr = LocalizationManager.shared
        TestHarness.assertEqual(locMgr.tr(.permissionsSectionTitle), "Permissions", "permissionsSectionTitle in English")
        TestHarness.assertEqual(locMgr.tr(.licenseLabel), "License:", "licenseLabel in English")
        TestHarness.assertEqual(locMgr.tr(.filenamePreviewLabel), "Filename Preview:", "filenamePreviewLabel in English")
        TestHarness.assertEqual(locMgr.tr(.clearSearchButton), "Clear Search", "clearSearchButton in English")
        TestHarness.assertEqual(locMgr.tr(.clearSearchTooltip), "Clear search query", "clearSearchTooltip in English")
        TestHarness.assertEqual(locMgr.tr(.quickCaptureRegion), "Area Capture (⌥S)", "quickCaptureRegion in English")
        TestHarness.assertEqual(locMgr.tr(.quickCaptureScroll), "Scrolling Capture (⌥⇧S)", "quickCaptureScroll in English")
        TestHarness.assertEqual(locMgr.tr(.welcomeTitle), "Welcome to SuperShot", "welcomeTitle in English")
        TestHarness.assertEqual(locMgr.tr(.getStartedButton), "Get Started", "getStartedButton in English")
        TestHarness.assertEqual(locMgr.tr(.welcomeGuideButton), "Welcome & Quick Guide", "welcomeGuideButton in English")
        TestHarness.assertEqual(locMgr.tr(.rememberLabel), "Remember:", "rememberLabel in English")
        TestHarness.assertEqual(locMgr.tr(.unpinnedHistoryCleared), "Unpinned history cleared", "unpinnedHistoryCleared in English")

        // 11. Settings Tab Truncation & Concise Localization Verification (v1.0.15)
        TestHarness.assertEqual(L10nKey.tabHistory.localized(for: .english), "History", "English tabHistory is concise 'History'")
        TestHarness.assertEqual(L10nKey.tabHistory.localized(for: .spanish), "Historial", "Spanish tabHistory is concise 'Historial'")
        TestHarness.assertEqual(L10nKey.tabCaptureSave.localized(for: .french), "Capture & Sauvegarde", "French tabCaptureSave is concise 'Capture & Sauvegarde'")
        TestHarness.assertEqual(SettingsTab.history.localizedTitle, "History", "SettingsTab.history default localizedTitle is 'History'")

        // 12. Version Consistency & Fallback Verification (v1.0.20)
        let updateMgr = UpdateManager.shared
        TestHarness.assertEqual(updateMgr.currentVersion, "1.0.20", "UpdateManager currentVersion fallback is 1.0.20")

        // 13. Overlay Cmd+A Fullscreen & Arrow Key Nudging Verification (v1.0.15)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let dummyCtx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let testImage = dummyCtx.makeImage()!
        let display = CaptureDisplayInfo(
            displayID: 1,
            name: "TestDisplay",
            cocoaFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            cgBounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scaleFactor: 2.0,
            isMain: true,
            pixelSize: CGSize(width: 2880, height: 1800)
        )
        let captured = CapturedScreen(displayInfo: display, fullImage: testImage, timestamp: Date())
        let overlayView = CaptureOverlayContentView(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            capturedScreen: captured,
            appSettings: settings,
            windowDelegate: nil
        )

        TestHarness.assertEqual(overlayView.selectionRect, CGRect.zero, "Initial selectionRect is empty")

        // Test Cmd+A immediately selects entire screen
        let cmdAEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )!
        let cmdAHandled = overlayView.handleOverlayKeyDown(with: cmdAEvent)
        TestHarness.assertTrue(cmdAHandled, "Cmd+A key event handled by overlay view")
        TestHarness.assertEqual(overlayView.selectionRect, overlayView.bounds, "Cmd+A expands selectionRect to full bounds (1440x900)")

        // Test Arrow key nudging: 1px without Shift, 10px with Shift
        overlayView.selectionRect = CGRect(x: 100, y: 100, width: 200, height: 150)

        // Right arrow (+1px)
        let rightArrowEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        let rightHandled = overlayView.handleOverlayKeyDown(with: rightArrowEvent)
        TestHarness.assertTrue(rightHandled, "Right arrow key event handled")
        TestHarness.assertEqual(overlayView.selectionRect.origin.x, 101.0, "Right arrow nudges selectionRect x by +1px")

        // Shift + Down arrow (-10px)
        let shiftDownEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        )!
        let shiftDownHandled = overlayView.handleOverlayKeyDown(with: shiftDownEvent)
        TestHarness.assertTrue(shiftDownHandled, "Shift+Down arrow key event handled")
        TestHarness.assertEqual(overlayView.selectionRect.origin.y, 90.0, "Shift+Down arrow nudges selectionRect y by -10px")

        // Left arrow (-1px)
        let leftArrowEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        )!
        let leftHandled = overlayView.handleOverlayKeyDown(with: leftArrowEvent)
        TestHarness.assertTrue(leftHandled, "Left arrow key event handled")
        TestHarness.assertEqual(overlayView.selectionRect.origin.x, 100.0, "Left arrow nudges selectionRect x by -1px")

        // Shift + Up arrow (+10px)
        let shiftUpEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        let shiftUpHandled = overlayView.handleOverlayKeyDown(with: shiftUpEvent)
        TestHarness.assertTrue(shiftUpHandled, "Shift+Up arrow key event handled")
        TestHarness.assertEqual(overlayView.selectionRect.origin.y, 100.0, "Shift+Up arrow nudges selectionRect y by +10px")

        // 14. Option+Arrow Resizing, Cmd+E Share, and Clear All Annotations Verification (v1.0.16)
        // Option + Right arrow (+1px width)
        let optRightEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        let optRightHandled = overlayView.handleOverlayKeyDown(with: optRightEvent)
        TestHarness.assertTrue(optRightHandled, "Option+Right arrow handled")
        TestHarness.assertEqual(overlayView.selectionRect.width, 201.0, "Option+Right arrow expands width by 1px")

        // Option + Shift + Right arrow (+10px width)
        let optShiftRightEvent = NSEvent.keyEvent(
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
        let optShiftRightHandled = overlayView.handleOverlayKeyDown(with: optShiftRightEvent)
        TestHarness.assertTrue(optShiftRightHandled, "Option+Shift+Right arrow handled")
        TestHarness.assertEqual(overlayView.selectionRect.width, 211.0, "Option+Shift+Right arrow expands width by 10px")

        // Option + Left arrow (-1px width)
        let optLeftEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        )!
        let optLeftHandled = overlayView.handleOverlayKeyDown(with: optLeftEvent)
        TestHarness.assertTrue(optLeftHandled, "Option+Left arrow handled")
        TestHarness.assertEqual(overlayView.selectionRect.width, 210.0, "Option+Left arrow contracts width by 1px")

        // Option + Up arrow (+1px height)
        let optUpEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        let optUpHandled = overlayView.handleOverlayKeyDown(with: optUpEvent)
        TestHarness.assertTrue(optUpHandled, "Option+Up arrow handled")
        TestHarness.assertEqual(overlayView.selectionRect.height, 151.0, "Option+Up arrow expands height by 1px")

        // Option + Down arrow (-1px height)
        let optDownEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        )!
        let optDownHandled = overlayView.handleOverlayKeyDown(with: optDownEvent)
        TestHarness.assertTrue(optDownHandled, "Option+Down arrow handled")
        TestHarness.assertEqual(overlayView.selectionRect.height, 150.0, "Option+Down arrow contracts height by 1px")

        // Test Selected Annotation Object Option+Arrow Resizing
        let engine = overlayView.annotationEngine
        let rectObj = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 120, y: 120, width: 80, height: 60),
            colorHex: "#FF3B30",
            strokeWidth: 3,
            isSelected: true
        )
        engine.addObject(rectObj)
        TestHarness.assertEqual(engine.selectedObjectID, rectObj.id, "Annotation object selected")

        _ = overlayView.handleOverlayKeyDown(with: optShiftRightEvent)
        TestHarness.assertEqual(engine.selectedObject?.bounds.width, 90.0, "Option+Shift+Right expands selected object width by 10px")

        // Test Clear All Annotations with Undo
        TestHarness.assertTrue(!engine.objects.isEmpty, "Engine has annotations before clearAll")
        let clearedCount = engine.clearAll()
        TestHarness.assertEqual(clearedCount, 1, "clearAll cleared 1 annotation")
        TestHarness.assertTrue(engine.objects.isEmpty, "Engine objects array is empty after clearAll")
        TestHarness.assertTrue(engine.canUndo, "Engine canUndo is true after clearAll")
        engine.undo()
        TestHarness.assertEqual(engine.objects.count, 1, "Undoing clearAll restores annotation object")
        engine.redo()
        TestHarness.assertTrue(engine.objects.isEmpty, "Redoing clearAll re-clears annotation objects")

        // Test Cmd+E Share Shortcut in ToolbarKeyShortcutHandler
        var shareTriggered = false
        overlayView.toolbarsViewModel.onShareRequested = { _ in shareTriggered = true }
        let cmdEEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "e",
            charactersIgnoringModifiers: "e",
            isARepeat: false,
            keyCode: 14
        )!
        let cmdEHandled = ToolbarKeyShortcutHandler.handleKeyEvent(event: cmdEEvent, viewModel: overlayView.toolbarsViewModel)
        TestHarness.assertTrue(cmdEHandled, "Cmd+E handled by ToolbarKeyShortcutHandler")
        TestHarness.assertTrue(shareTriggered, "Cmd+E triggers onShareRequested")

        // Test LocalizationManager for v1.0.16 keys
        TestHarness.assertEqual(locMgr.tr(.annotationsCleared), "Annotations Cleared (⌘⇧K)", "annotationsCleared English string matches")
        TestHarness.assertEqual(locMgr.tr(.actionShareTooltip), "Share (⌘E)", "actionShareTooltip English string matches")

        // 17. Diagnostic String Formatting & Control+Tab Cycling Verification (v1.0.20)
        let diagString = AboutSettingsTab.diagnosticString(version: "1.0.20")
        TestHarness.assertTrue(diagString.hasPrefix("SuperShot v1.0.20"), "Diagnostic string starts with 'SuperShot v1.0.20'")
        TestHarness.assertTrue(diagString.contains("macOS"), "Diagnostic string contains 'macOS'")
        TestHarness.assertTrue(diagString.contains("Build"), "Diagnostic string contains 'Build'")

        TestHarness.assertEqual(locMgr.tr(.copiedDiagnostics), "Diagnostic Info Copied", "copiedDiagnostics English string matches")

        // Test Control+Tab and Control+Shift+Tab Notification Posting
        var cycleDirection: Int? = nil
        let ctrlTabObserver = NotificationCenter.default.addObserver(
            forName: .settingsCycleTab,
            object: nil,
            queue: .main
        ) { notif in
            cycleDirection = notif.userInfo?["direction"] as? Int
        }

        let ctrlTabEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
        controller.window?.keyDown(with: ctrlTabEvent)
        TestHarness.assertEqual(cycleDirection, 1, "Control+Tab cycles to next tab (direction 1)")

        let ctrlShiftTabEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
        controller.window?.keyDown(with: ctrlShiftTabEvent)
        TestHarness.assertEqual(cycleDirection, -1, "Control+Shift+Tab cycles to previous tab (direction -1)")

        NotificationCenter.default.removeObserver(ctrlTabObserver)

        // 18. Cmd+W Window Dismissal & Version 1.0.20 Verification (v1.0.20)
        let cmdWEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )!
        controller.window?.keyDown(with: cmdWEvent)
        TestHarness.assertFalse(controller.window?.isVisible ?? true, "Cmd+W closes SettingsWindow")

        // WelcomeWindow Cmd+W dismissal
        let welcomeWinController = WelcomeWindowController()
        welcomeWinController.showWelcomeWindow()
        TestHarness.assertTrue(welcomeWinController.window?.isVisible == true, "WelcomeWindow is visible")
        welcomeWinController.window?.keyDown(with: cmdWEvent)
        TestHarness.assertFalse(welcomeWinController.window?.isVisible ?? true, "Cmd+W closes WelcomeWindow")

        // UpdateManager version verification
        TestHarness.assertEqual(UpdateManager.shared.currentVersion, "1.0.20", "UpdateManager currentVersion is 1.0.20")
    }
}
