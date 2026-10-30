import Foundation
import SuperShotCore

public struct AppSettingsTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("AppSettings Persistence & Preset Management")

        try? FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        let settingsURL = sandboxDir.appendingPathComponent("test_settings.json")
        let settings = AppSettings(settingsURL: settingsURL)

        // 1. Initial default state
        TestHarness.assertEqual(settings.activeColorHex, "#FF3B30", "Default activeColorHex is #FF3B30")
        TestHarness.assertEqual(settings.activeStrokeWidth, 3.0, "Default stroke width is 3.0")
        TestHarness.assertEqual(settings.activeFontSize, 28.0, "Default font size is 28.0")
        TestHarness.assertEqual(settings.presets.count, 8, "Initial presets count is 8")
        TestHarness.assertEqual(settings.maxScrollHeightPx, 15000, "Default maxScrollHeightPx is 15000")
        TestHarness.assertEqual(settings.saveFormat, .png, "Default saveFormat is PNG")

        // 2. Preset management and 16 preset ceiling
        for i in 9...16 {
            let p = ColorPreset(name: "Custom \(i)", hex: String(format: "#%06X", i * 1000))
            let added = settings.addPreset(p)
            TestHarness.assertTrue(added, "Adding preset \(i) succeeds")
        }
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count reached 16")

        // Attempting to add 17th preset must fail
        let overflowPreset = ColorPreset(name: "Overflow", hex: "#FFFFFF")
        let overflowResult = settings.addPreset(overflowPreset)
        TestHarness.assertFalse(overflowResult, "Adding 17th preset is rejected")
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count clamped to 16 ceiling")

        // 2b. Regression Test: Updating existing preset name at capacity 16 succeeds, 17th unique rejected
        let firstDefaultHex = settings.presets[0].hex
        let updatedName = "Updated Red Preset"
        let updateResult = settings.addPreset(ColorPreset(name: updatedName, hex: firstDefaultHex))
        TestHarness.assertTrue(updateResult, "addPreset must return true when updating an existing preset name at capacity 16")
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count must remain 16 after updating existing preset")
        TestHarness.assertEqual(settings.presets[0].name, updatedName, "Existing preset name must be updated in-place")

        // Verify case-insensitive and un-prefixed hex match updates name at capacity 16
        let lowerHexNoHash = firstDefaultHex.replacingOccurrences(of: "#", with: "").lowercased()
        let caseInsensitiveUpdate = settings.addPreset(ColorPreset(name: "Case Insensitive Red", hex: lowerHexNoHash))
        TestHarness.assertTrue(caseInsensitiveUpdate, "addPreset must match normalized hex case-insensitively and update name at capacity 16")
        TestHarness.assertEqual(settings.presets[0].name, "Case Insensitive Red", "Preset name updated via case-insensitive hex at capacity 16")

        // Verify 17th unique preset is strictly rejected
        let unique17Preset = ColorPreset(name: "17th Unique Preset", hex: "#112233")
        let unique17Result = settings.addPreset(unique17Preset)
        TestHarness.assertFalse(unique17Result, "addPreset must return false when adding a 17th unique preset at capacity 16")
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count must remain clamped at 16 ceiling")
        TestHarness.assertFalse(settings.presets.contains(where: { $0.hex == "#112233" }), "17th unique preset must not be added to presets array")

        // 3. Preset deletion and reset
        let toDeleteID = settings.presets[0].id
        let deleted = settings.deletePreset(id: toDeleteID)
        TestHarness.assertTrue(deleted, "Preset deleted successfully")
        TestHarness.assertEqual(settings.presets.count, 15, "Presets count decreased to 15")

        settings.resetPresets()
        TestHarness.assertEqual(settings.presets.count, 8, "Reset presets restores 8 standard defaults")

        // 4. Clamping bounds
        settings.activeStrokeWidth = -5.0
        TestHarness.assertEqual(settings.activeStrokeWidth, 1.0, "Negative stroke width clamped to 1.0")
        settings.maxScrollHeightPx = 50000
        TestHarness.assertEqual(settings.maxScrollHeightPx, 30000, "Excessive scroll height clamped to 30000")

        // 5. Persistence across cold restart
        settings.activeColorHex = "#007AFF"
        settings.activeStrokeWidth = 5.0
        settings.saveFormat = .jpeg
        try? settings.saveSynchronously()

        let reloadedSettings = AppSettings(settingsURL: settingsURL)
        TestHarness.assertEqual(reloadedSettings.activeColorHex, "#007AFF", "Persisted activeColorHex reloaded")
        TestHarness.assertEqual(reloadedSettings.activeStrokeWidth, 5.0, "Persisted stroke width reloaded")
        TestHarness.assertEqual(reloadedSettings.saveFormat, .jpeg, "Persisted save format reloaded")
    }
}
