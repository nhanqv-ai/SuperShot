import Foundation
import CoreGraphics
import AppKit

#if canImport(SuperShotCore)
import SuperShotCore
#endif

/// Tier 2: Boundary & Corner Cases Test Suite for SuperShot
public struct BoundaryTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Tier 2: Boundary & Corner Cases")
        
        let storage = StorageManagerTests.MockStorageManager(baseDirectory: sandboxDir, capacity: 5)
        
        // Boundary 1: Micro 1x1 pixel dimension
        let microItem = StorageManagerTests.TestShotItem(title: "Micro 1x1", width: 1, height: 1)
        storage.addShot(item: microItem, imageData: nil)
        TestHarness.assertEqual(storage.items.first?.width, 1, "Micro 1x1 width handled cleanly")
        TestHarness.assertEqual(storage.items.first?.height, 1, "Micro 1x1 height handled cleanly")
        
        // Boundary 2: Huge 30,000 px tall image dimensions
        let hugeTallItem = StorageManagerTests.TestShotItem(title: "Tall 30k", width: 1280, height: 30000)
        storage.addShot(item: hugeTallItem, imageData: nil)
        TestHarness.assertEqual(storage.items.first?.height, 30000, "30,000 px tall screenshot dimension stored without integer overflow")
        
        // Boundary 3: Special characters and punctuation in title/query
        let specialTitle = "Error: null pointer at 0x0000 & <script>alert('xss')</script> [regex]*+?"
        let specialItem = StorageManagerTests.TestShotItem(title: specialTitle)
        storage.addShot(item: specialItem, imageData: nil)
        TestHarness.assertEqual(storage.items.first?.title, specialTitle, "Special characters and symbols preserved verbatim")
        
        // Boundary 4: Search with regex meta-characters treated as literal substrings
        let regexResults = storage.search(query: "[regex]*+?")
        TestHarness.assertEqual(regexResults.count, 1, "Search treats regex metacharacters as literal substrings")
        
        // Boundary 5: Empty search query returns all items
        let allResults = storage.search(query: "")
        TestHarness.assertEqual(allResults.count, storage.items.count, "Empty search query returns 100% of store items")
        
        // Boundary 6: Capacity boundary limit (minimum 1)
        storage.capacity = 0 // Attempts setting 0
        TestHarness.assertTrue(storage.capacity >= 1, "Capacity clamps to safe minimum bound >= 1")
        
        // Boundary 7: Corrupted metadata.json recovery
        let corruptSandbox = sandboxDir.appendingPathComponent("CorruptRecovery")
        try? FileManager.default.createDirectory(at: corruptSandbox, withIntermediateDirectories: true)
        let corruptMetadataURL = corruptSandbox.appendingPathComponent("metadata.json")
        try? "MALFORMED_JSON_NOT_VALID_ARRAY{{{".data(using: .utf8)?.write(to: corruptMetadataURL)
        
        let recoveredStorage = StorageManagerTests.MockStorageManager(baseDirectory: corruptSandbox, capacity: 10)
        TestHarness.assertEqual(recoveredStorage.items.count, 0, "Corrupt metadata.json gracefully recovers with empty items array without crashing")
        try? FileManager.default.removeItem(at: corruptSandbox)
        
        // Boundary 8: Hex parsing boundary validation
        let invalidHexPreset = ColorPresetTests.PresetModel(name: "Invalid", hex: "NOT_HEX")
        TestHarness.assertNil(invalidHexPreset.parseRGB(), "Invalid hex string returns nil from RGB parser")
        
        let validHexPreset = ColorPresetTests.PresetModel(name: "Black", hex: "#000000")
        if let rgb = validHexPreset.parseRGB() {
            TestHarness.assertEqual(rgb.r, 0.0, "Black hex r=0.0")
            TestHarness.assertEqual(rgb.g, 0.0, "Black hex g=0.0")
            TestHarness.assertEqual(rgb.b, 0.0, "Black hex b=0.0")
        } else {
            TestHarness.recordFail("Black Hex Parse", reason: "parseRGB failed on #000000")
        }
    }
}
