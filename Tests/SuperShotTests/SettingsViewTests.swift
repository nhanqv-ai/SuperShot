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
    }
}
