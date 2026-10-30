import Foundation
import AppKit
import Carbon
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
        let appTitle = LocalizationManager.shared.tr(.appTitle)
        let action = LocalizationManager.shared.tr(.menuCapture)
        let shortcut = mockHotKey.shortcut(for: .inPlaceCapture)?.displayString ?? "⌥S"
        TestHarness.assertEqual(manager.statusItem.button?.toolTip, "\(appTitle) - \(action) (\(shortcut))", "Default tooltip contains shortcut")

        // 2. Context Menu Structure & Items
        let menu = manager.contextMenu
        TestHarness.assertEqual(menu.title, "SuperShot", "Menu title matches")

        let itemTitles = menu.items.map { $0.title }
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuCapture)), "Context menu contains Take Screenshot")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuScrollingCapture)), "Context menu contains Scrolling Screenshot")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuShowHistory)), "Context menu contains Show History")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuPreferences)), "Context menu contains Preferences...")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuClearHistory)), "Context menu contains Clear Unpinned History")
        TestHarness.assertFalse(itemTitles.contains(LocalizationManager.shared.tr(.welcomeGuideButton)), "Context menu does not contain Welcome & Quick Guide")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuCheckUpdates)), "Context menu contains Check for Updates...")
        TestHarness.assertTrue(itemTitles.contains(LocalizationManager.shared.tr(.menuQuit)), "Context menu contains Quit SuperShot")

        // Verify menuNeedsUpdate never creates duplicate Check for Updates items
        manager.menuNeedsUpdate(menu)
        let checkUpdatesTitle = LocalizationManager.shared.tr(.menuCheckUpdates)
        let checkUpdatesCount = menu.items.filter { !$0.isSeparatorItem && $0.title == checkUpdatesTitle }.count
        TestHarness.assertEqual(checkUpdatesCount, 1, "menuNeedsUpdate maintains exactly 1 Check for Updates menu item")
        let nonSeparatorTitles = menu.items.filter { !$0.isSeparatorItem }.map { $0.title }
        TestHarness.assertEqual(nonSeparatorTitles.count, Set(nonSeparatorTitles).count, "All non-separator context menu items have unique titles after menuNeedsUpdate")

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

        // 6. Dynamic Localized Status Item ToolTip (F9)
        LocalizationManager.shared.setLanguage(.vietnamese)
        TestHarness.assertEqual(manager.statusItem.button?.toolTip, "SuperShot - Chụp màn hình (⌥S)", "Status item tooltip dynamically updates on language change")
        LocalizationManager.shared.setLanguage(.english)
        TestHarness.assertEqual(manager.statusItem.button?.toolTip, "SuperShot - Capture Screen (⌥S)", "Status item tooltip returns to English on language change")

        // 7. Integration: HotKeyManager.shared registration with StatusItemManager (no deadlock)
        let realHotKey = HotKeyManager.shared
        let liveStatusItemManager = StatusItemManager(
            contentViewController: dummyVC,
            storageManager: storage,
            appSettings: settings,
            hotKeyManager: realHotKey,
            previousAppTracker: previousApp
        )

        let registered = realHotKey.register(
            action: .inPlaceCapture,
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(optionKey)
        )
        TestHarness.assertTrue(registered, "HotKeyManager.shared registers inPlaceCapture successfully")
        let liveTooltip = liveStatusItemManager.statusItem.button?.toolTip
        TestHarness.assertNotNil(liveTooltip, "StatusItemManager tooltip is present")
        TestHarness.assertTrue(liveTooltip?.contains("⌥S") == true, "StatusItemManager tooltip updated to '⌥S' without deadlock")

        // Unregister and ensure notification handler executes without deadlock
        realHotKey.unregister(action: .inPlaceCapture)
        let unregTooltip = liveStatusItemManager.statusItem.button?.toolTip
        TestHarness.assertNotNil(unregTooltip, "StatusItemManager tooltip is present after unregister")

        // Restore default hotkeys for subsequent tests
        realHotKey.registerDefaults()
    }
}
