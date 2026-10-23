import Foundation
import AppKit
import SuperShotCore
import SuperShot

public struct StatusItemTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("StatusItemManager & Context Menu Tests")

        let storage = StorageManager(baseDirectory: sandboxDir, initialCapacity: 50)
        let settings = AppSettings(settingsURL: sandboxDir.appendingPathComponent("settings.json"))
        let mockHotKey = MockHotKeyManager()
        let previousApp = PreviousAppTracker()

        let dummyVC = NSViewController()
        dummyVC.preferredContentSize = NSSize(width: 380, height: 600)

        let manager = StatusItemManager(
            contentViewController: dummyVC,
            storageManager: storage,
            appSettings: settings,
            hotKeyManager: mockHotKey,
            previousAppTracker: previousApp
        )

        // 1. Status Item Initialization
        TestHarness.assertNotNil(manager.statusItem.button, "Status item button created")
        TestHarness.assertNotNil(manager.statusItem.button?.image, "Status item icon configured")
        TestHarness.assertTrue(manager.statusItem.button?.image?.isTemplate == true, "Icon is configured as template")
        TestHarness.assertEqual(manager.statusItem.button?.toolTip, "SuperShot - Screenshot & Annotate (Option+S)", "Default tooltip contains shortcut")

        // 2. Context Menu Structure & Items
        let menu = manager.contextMenu
        TestHarness.assertEqual(menu.title, "SuperShot", "Menu title matches")

        let itemTitles = menu.items.map { $0.title }
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuCapture)), "Context menu contains Take Screenshot")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuScrollingCapture)), "Context menu contains Scrolling Screenshot")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuShowHistory)), "Context menu contains Show History")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuPreferences)), "Context menu contains Preferences...")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuClearHistory)), "Context menu contains Clear Unpinned History")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuQuit)), "Context menu contains Quit SuperShot")

        // 3. Menu Item Shortcuts & Key Equivalents
        let prefsItem = menu.items.first(where: { $0.title == LocalizationManager.shared.tr(.menuPreferences) })
        TestHarness.assertEqual(prefsItem?.keyEquivalent, ",", "Preferences shortcut is Cmd+,")
        TestHarness.assertEqual(prefsItem?.keyEquivalentModifierMask, [.command], "Preferences modifier is Command")

        let quitItem = menu.items.first(where: { $0.title == LocalizationManager.shared.tr(.menuQuit) })
        TestHarness.assertEqual(quitItem?.keyEquivalent, "q", "Quit shortcut is Cmd+Q")
        TestHarness.assertEqual(quitItem?.keyEquivalentModifierMask, [.command], "Quit modifier is Command")

        // 4. Popover Dimensions & Properties
        TestHarness.assertEqual(manager.popover.behavior, .transient, "Popover behavior is transient")
        TestHarness.assertFalse(manager.popover.animates, "Popover animations disabled for snappy response")
        TestHarness.assertEqual(manager.popover.contentSize, NSSize(width: 380, height: 600), "Popover content size is 380x600")

        // 5. Callback Invocations
        var regionTriggered = false
        manager.onRegionCaptureRequested = { regionTriggered = true }
        if let captureMenuItem = manager.contextMenu.items.first(where: { $0.title == LocalizationManager.shared.tr(.menuCapture) }),
           let action = captureMenuItem.action {
            _ = captureMenuItem.target?.perform(action, with: nil)
        }
        TestHarness.assertTrue(regionTriggered, "Take Screenshot menu click fires onRegionCaptureRequested")

        var settingsTriggered = false
        manager.onOpenSettingsRequested = { settingsTriggered = true }
        if let action = prefsItem?.action {
            _ = prefsItem?.target?.perform(action, with: nil)
        }
        TestHarness.assertTrue(settingsTriggered, "Preferences menu click fires onOpenSettingsRequested")
    }
}
