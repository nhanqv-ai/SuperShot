import Foundation
import AppKit
import SwiftUI
import SuperShotCore

/// Unit and integration tests for ColorPreset data model, hex parsing,
/// preset limits (8 defaults, max 16 favorite presets), and AppSettings persistence.
public struct ColorPresetTests {
    // Model adapter for E2E / Boundary test suites
    public struct PresetModel: Codable, Equatable, Identifiable {
        public let id: UUID
        public var name: String
        public var hex: String
        private let rawHex: String
        
        public init(id: UUID = UUID(), name: String, hex: String) {
            self.id = id
            self.name = name
            self.rawHex = hex
            self.hex = ColorPreset.normalize(hex: hex)
        }
        
        public static var defaults: [PresetModel] {
            ColorPreset.defaults.map { PresetModel(id: $0.id, name: $0.name, hex: $0.hex) }
        }
        
        public func parseRGB() -> (r: Double, g: Double, b: Double)? {
            if !ColorPreset.isValid(hex: rawHex) { return nil }
            return ColorPreset.parseRGB(hex: hex)
        }
    }

    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("ColorPreset Specifications & Color Conversions")
        
        // 1. Defaults verification: exactly 8 presets
        let defaults = ColorPreset.defaults
        TestHarness.assertEqual(defaults.count, 8, "ColorPreset has exactly 8 high-contrast default presets")
        
        // 2. Specific expected default hex colors
        let expectedDefaults = [
            ("Red", "#FF3B30"),
            ("Orange", "#FF9500"),
            ("Yellow", "#FFCC00"),
            ("Green", "#34C759"),
            ("Blue", "#007AFF"),
            ("Indigo", "#5856D6"),
            ("Purple", "#AF52DE"),
            ("Black", "#000000")
        ]
        for (idx, expected) in expectedDefaults.enumerated() {
            TestHarness.assertEqual(defaults[idx].name, expected.0, "Default \(idx) name is \(expected.0)")
            TestHarness.assertEqual(defaults[idx].hex, expected.1, "Default \(idx) hex is \(expected.1)")
        }
        
        // 3. Hex validation
        TestHarness.assertTrue(ColorPreset.isValid(hex: "#FF3B30"), "Valid 6-digit hex with hash")
        TestHarness.assertTrue(ColorPreset.isValid(hex: "007AFF"), "Valid 6-digit hex without hash")
        TestHarness.assertTrue(ColorPreset.isValid(hex: "#F90"), "Valid 3-digit hex with hash")
        TestHarness.assertTrue(ColorPreset.isValid(hex: "ABC"), "Valid 3-digit hex without hash")
        TestHarness.assertFalse(ColorPreset.isValid(hex: "#12345"), "Invalid 5-digit hex")
        TestHarness.assertFalse(ColorPreset.isValid(hex: "#ZZZZZZ"), "Invalid characters hex")
        TestHarness.assertFalse(ColorPreset.isValid(hex: ""), "Empty string hex")
        
        // 4. Hex normalization
        TestHarness.assertEqual(ColorPreset.normalize(hex: "ff3b30"), "#FF3B30", "Lowercase 6-digit hex normalized to uppercase with hash")
        TestHarness.assertEqual(ColorPreset.normalize(hex: "#f90"), "#FF9900", "3-digit hex expanded and normalized")
        TestHarness.assertEqual(ColorPreset.normalize(hex: "  #007aff \n"), "#007AFF", "Padded hex trimmed and normalized")
        TestHarness.assertEqual(ColorPreset.normalize(hex: "INVALID"), "#FF3B30", "Invalid hex falls back to #FF3B30")
        
        // 5. Hex parsing and RGB conversion
        let redPreset = ColorPreset(name: "Red", hex: "#FF3B30")
        if let rgb = ColorPreset.parseRGB(hex: redPreset.hex) {
            TestHarness.assertTrue(abs(rgb.r - 1.0) < 0.01, "Red channel component parsed correctly as 1.0")
            TestHarness.assertTrue(abs(rgb.g - (59.0 / 255.0)) < 0.01, "Green channel component parsed correctly")
            TestHarness.assertTrue(abs(rgb.b - (48.0 / 255.0)) < 0.01, "Blue channel component parsed correctly")
        } else {
            TestHarness.recordFail("Hex Parsing #FF3B30", reason: "parseRGB() returned nil")
        }
        
        // 6. Color conversions
        let nsColor = redPreset.toNSColor()
        TestHarness.assertEqual(nsColor.colorSpace.colorSpaceModel, .rgb, "NSColor converted into RGB space")
        TestHarness.assertTrue(abs(Double(nsColor.redComponent) - 1.0) < 0.01, "NSColor red component matches")
        
        let swiftUIColor = redPreset.toColor()
        _ = swiftUIColor // Verify conversion compiles and succeeds
        TestHarness.recordPass("SwiftUI Color converted successfully")
        
        // 7. Codable round-trip
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try? encoder.encode(redPreset)
        TestHarness.assertNotNil(encoded, "ColorPreset encodes to JSON successfully")
        let decoded = encoded.flatMap { try? decoder.decode(ColorPreset.self, from: $0) }
        TestHarness.assertNotNil(decoded, "ColorPreset decodes from JSON successfully")
        TestHarness.assertEqual(decoded?.id, redPreset.id, "Decoded id matches")
        TestHarness.assertEqual(decoded?.name, redPreset.name, "Decoded name matches")
        TestHarness.assertEqual(decoded?.hex, redPreset.hex, "Decoded hex matches")
        
        // 8. Integration with AppSettings preset limits
        try? FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        let settingsFile = sandboxDir.appendingPathComponent("preset_test_settings.json")
        let settings = AppSettings(settingsURL: settingsFile)
        TestHarness.assertEqual(settings.presets.count, 8, "AppSettings initialized with 8 default presets")
        
        for i in 9...16 {
            let p = ColorPreset(name: "Custom \(i)", hex: String(format: "#%06X", i * 1000))
            let added = settings.addPreset(p)
            TestHarness.assertTrue(added, "Successfully added custom preset \(i)")
        }
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count reached max limit of 16")
        
        let overflowPreset = ColorPreset(name: "Overflow", hex: "#FFFFFF")
        let overflowAdded = settings.addPreset(overflowPreset)
        TestHarness.assertFalse(overflowAdded, "17th preset addition rejected beyond 16 limit")
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count remains clamped to 16")
        
        let firstID = settings.presets[0].id
        let deleted = settings.deletePreset(id: firstID)
        TestHarness.assertTrue(deleted, "Deleted preset successfully")
        TestHarness.assertEqual(settings.presets.count, 15, "Presets count decreased to 15")
        
        settings.resetPresets()
        TestHarness.assertEqual(settings.presets.count, 8, "Reset presets restored 8 default presets")
    }
}
