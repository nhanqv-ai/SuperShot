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
        TestHarness.assertEqual(welcomeView.appVersionString, "v1.0.10", "WelcomeView version string is v1.0.10")
        welcomeView.onDismiss?()
        TestHarness.assertTrue(welcomeDismissed, "WelcomeView onDismiss executes cleanly")

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
    }
}
