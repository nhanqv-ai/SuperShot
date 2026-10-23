import Foundation
import Carbon
import AppKit
import SuperShotCore

/// Mock HotKeyManager for isolated headless testing without invoking Carbon C APIs.
public final class MockHotKeyManager: HotKeyManaging {
    public var onAction: ((HotKeyAction) -> Void)?
    public private(set) var registrations: [HotKeyAction: HotKeyShortcut] = [:]

    public init() {}

    public func register(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) -> Bool {
        registrations[action] = HotKeyShortcut(keyCode: keyCode, carbonModifiers: modifiers)
        return true
    }

    public func unregister(action: HotKeyAction) {
        registrations.removeValue(forKey: action)
    }

    public func unregisterAll() {
        registrations.removeAll()
    }

    public func registerDefaults() {
        register(action: .inPlaceCapture, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey))
        register(action: .scrollingCapture, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey))
    }

    public func isRegistered(action: HotKeyAction) -> Bool {
        return registrations[action] != nil
    }

    public func shortcut(for action: HotKeyAction) -> HotKeyShortcut? {
        return registrations[action]
    }
}

public struct HotKeyManagerTests {
    public static func run() {
        TestHarness.startSuite("HotKeyManager & Global Shortcuts Tests")

        // 1. MockHotKeyManager registration and retrieval
        let mock = MockHotKeyManager()
        mock.registerDefaults()

        TestHarness.assertTrue(mock.isRegistered(action: .inPlaceCapture), "In-place capture registered by default")
        TestHarness.assertTrue(mock.isRegistered(action: .scrollingCapture), "Scrolling capture registered by default")

        let inPlaceShortcut = mock.shortcut(for: .inPlaceCapture)
        TestHarness.assertNotNil(inPlaceShortcut, "In-place shortcut found")
        TestHarness.assertEqual(inPlaceShortcut?.keyCode, UInt32(kVK_ANSI_S), "In-place keyCode is 'S'")
        TestHarness.assertEqual(inPlaceShortcut?.carbonModifiers, UInt32(optionKey), "In-place modifier is Option")
        TestHarness.assertEqual(inPlaceShortcut?.displayString, "⌥S", "In-place display glyph is ⌥S")

        let scrollShortcut = mock.shortcut(for: .scrollingCapture)
        TestHarness.assertNotNil(scrollShortcut, "Scrolling shortcut found")
        TestHarness.assertEqual(scrollShortcut?.keyCode, UInt32(kVK_ANSI_S), "Scrolling keyCode is 'S'")
        TestHarness.assertEqual(scrollShortcut?.carbonModifiers, UInt32(optionKey | shiftKey), "Scrolling modifier is Option+Shift")
        TestHarness.assertEqual(scrollShortcut?.displayString, "⌥⇧S", "Scrolling display glyph is ⌥⇧S")

        // 2. Unregister single and all
        mock.unregister(action: .inPlaceCapture)
        TestHarness.assertFalse(mock.isRegistered(action: .inPlaceCapture), "In-place capture unregisters cleanly")
        TestHarness.assertTrue(mock.isRegistered(action: .scrollingCapture), "Scrolling capture remains registered")

        mock.unregisterAll()
        TestHarness.assertFalse(mock.isRegistered(action: .scrollingCapture), "All hotkeys unregistered")

        // 3. Modifier Converter testing
        let carbonOption = UInt32(optionKey)
        let cocoaOption = HotKeyModifierConverter.toCocoaModifiers(carbonOption)
        TestHarness.assertTrue(cocoaOption.contains(.option), "Carbon option maps to Cocoa .option")
        TestHarness.assertFalse(cocoaOption.contains(.command), "Carbon option does not contain .command")

        let cocoaShiftCmd: NSEvent.ModifierFlags = [.shift, .command]
        let carbonShiftCmd = HotKeyModifierConverter.toCarbonModifiers(cocoaShiftCmd)
        TestHarness.assertEqual(carbonShiftCmd, UInt32(shiftKey | cmdKey), "Cocoa shift+cmd maps to Carbon shiftKey | cmdKey")

        // 4. Action trigger simulation
        var triggeredAction: HotKeyAction?
        mock.onAction = { action in
            triggeredAction = action
        }
        mock.onAction?(.scrollingCapture)
        TestHarness.assertEqual(triggeredAction, .scrollingCapture, "Action callback dispatches correctly")

        // 5. Shared HotKeyManager API sanity
        let realMgr = HotKeyManager.shared
        TestHarness.assertNotNil(realMgr, "HotKeyManager.shared singleton instantiated")
        TestHarness.assertEqual(HotKeyAction.inPlaceCapture.identifier, "inPlaceCapture", "InPlaceCapture identifier matches")
        TestHarness.assertEqual(HotKeyAction.scrollingCapture.identifier, "scrollingCapture", "ScrollingCapture identifier matches")
    }
}
