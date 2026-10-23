import Foundation
import CoreGraphics
import AppKit

#if canImport(SuperShotCore)
import SuperShotCore
#endif

/// Tier 3: Pairwise Combinations & Cross-Feature Interactions Test Suite
public struct PairwiseTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Tier 3: Pairwise Combinations & Cross-Feature Interactions")
        
        // Pairwise 1: F05 (ColorPreset) + F21 (Select/Move) & Vector Annotation
        let engine = AnnotationEngineTests.MockAnnotationEngine()
        let rect = AnnotationEngineTests.VectorObject(
            tool: .rectangle,
            rect: CGRect(x: 100, y: 100, width: 200, height: 100),
            colorHex: "#FF3B30"
        )
        engine.addObject(rect)
        _ = engine.selectObject(at: CGPoint(x: 150, y: 150))
        let greenPreset = ColorPresetTests.PresetModel.defaults.first(where: { $0.name == "Green" })
        engine.recolorSelected(newHex: greenPreset?.hex ?? "#34C759")
        let updatedRectColor = engine.objects.first?.colorHex
        TestHarness.assertEqual(updatedRectColor, "#34C759", "Pairwise 1: Selected vector object updated with Green preset (#34C759)")
        
        // Pairwise 2: F09 (StorageManager) + F11 (Pinned Protection)
        let storage = StorageManagerTests.MockStorageManager(baseDirectory: sandboxDir.appendingPathComponent("PairwiseStorage"), capacity: 3)
        let pinnedItem = StorageManagerTests.TestShotItem(title: "Pinned Important", isPinned: true)
        storage.addShot(item: pinnedItem, imageData: nil)
        
        for i in 1...5 {
            let unpinned = StorageManagerTests.TestShotItem(title: "Unpinned \(i)", isPinned: false)
            storage.addShot(item: unpinned, imageData: nil)
        }
        TestHarness.assertEqual(storage.recentItems.count, 3, "Pairwise 2: Unpinned capacity clamped strictly at 3")
        TestHarness.assertTrue(storage.items.contains(where: { $0.id == pinnedItem.id }), "Pairwise 2: Pinned item survived overflow of 5 unpinned items")
        
        // Pairwise 3: F22 (Rectangle) + F30 (Undo/Redo)
        engine.undo() // Undoes recolor
        TestHarness.assertEqual(engine.objects.first?.colorHex, "#FF3B30", "Pairwise 3: Undo reverted color back to original #FF3B30")
        engine.redo() // Redoes recolor
        TestHarness.assertEqual(engine.objects.first?.colorHex, "#34C759", "Pairwise 3: Redo restored Green color #34C759")
        
        // Pairwise 4: F50 (Search Filter) + F53 (Number Shortcuts 1..9)
        let sampleHistory = [
            StorageManagerTests.TestShotItem(title: "Bug Report Terminal"),
            StorageManagerTests.TestShotItem(title: "Safari Documentation"),
            StorageManagerTests.TestShotItem(title: "Terminal Output Error"),
            StorageManagerTests.TestShotItem(title: "Slack Discussion")
        ]
        let query = "terminal"
        let filtered = sampleHistory.filter { $0.title.lowercased().contains(query) }
        TestHarness.assertEqual(filtered.count, 2, "Pairwise 4: Search filtered to 2 matching items")
        
        let shortcut1 = filtered.indices.contains(0) ? filtered[0] : nil
        let shortcut2 = filtered.indices.contains(1) ? filtered[1] : nil
        let shortcut3 = filtered.indices.contains(2) ? filtered[2] : nil
        TestHarness.assertEqual(shortcut1?.title, "Bug Report Terminal", "Shortcut 1 maps to 1st visible filtered item")
        TestHarness.assertEqual(shortcut2?.title, "Terminal Output Error", "Shortcut 2 maps to 2nd visible filtered item")
        TestHarness.assertNil(shortcut3, "Shortcut 3 is nil since only 2 items are visible")
    }
}
