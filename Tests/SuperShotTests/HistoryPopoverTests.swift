import Foundation
import CoreGraphics
import SuperShotCore
import SuperShot

public struct HistoryPopoverTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("HistoryPopover & Selection Navigation Tests")

        let storage = StorageManager(baseDirectory: sandboxDir, initialCapacity: 10)
        let sampleImage = MockScreenCaptureProvider.createSyntheticImage(size: CGSize(width: 400, height: 300))!

        // Seed storage with 5 items: 2 pinned, 3 unpinned
        let item1 = try! storage.save(image: sampleImage, sourceApp: "Xcode", captureType: .region, tags: ["code", "bug"])
        let item2 = try! storage.save(image: sampleImage, sourceApp: "Safari", captureType: .scrolling, tags: ["web", "docs"])
        let item3 = try! storage.save(image: sampleImage, sourceApp: "Terminal", captureType: .region, tags: ["cli", "log"])
        let _ = try! storage.save(image: sampleImage, sourceApp: "Notes", captureType: .region, tags: ["memo"])
        let item5 = try! storage.save(image: sampleImage, sourceApp: "Slack", captureType: .region, tags: ["chat"])

        storage.togglePin(id: item1.id)
        storage.togglePin(id: item3.id)

        // 1. Pinned vs Recent Partitioning
        TestHarness.assertEqual(storage.pinnedItems.count, 2, "2 items are pinned")
        TestHarness.assertEqual(storage.recentItems.count, 3, "3 items are recent unpinned")
        TestHarness.assertTrue(storage.pinnedItems.contains(where: { $0.id == item1.id }), "item1 is in pinned")
        TestHarness.assertTrue(storage.pinnedItems.contains(where: { $0.id == item3.id }), "item3 is in pinned")

        // 2. Search Query Filtering
        let xcodeResults = storage.search(query: "Xcode")
        TestHarness.assertEqual(xcodeResults.count, 1, "Search for 'Xcode' yields exactly 1 item")
        TestHarness.assertEqual(xcodeResults.first?.id, item1.id, "Matching item is item1")

        let tagResults = storage.search(query: "chat")
        TestHarness.assertEqual(tagResults.count, 1, "Search for tag 'chat' yields item5")
        TestHarness.assertEqual(tagResults.first?.id, item5.id, "Matching item is item5")

        let emptyResults = storage.search(query: "")
        TestHarness.assertEqual(emptyResults.count, 5, "Empty search query yields all 5 items")

        // 3. Circular Index Navigation via ShortcutNavigator
        let total = 5
        var selectedIdx: Int? = 0

        // Step Up from 0 wraps to 4 (bottom)
        selectedIdx = ShortcutNavigator.stepUp(currentIndex: selectedIdx, visibleCount: total)
        TestHarness.assertEqual(selectedIdx, 4, "Up Arrow from top wraps circularly to bottom (index 4)")

        // Step Down from 4 wraps to 0 (top)
        selectedIdx = ShortcutNavigator.stepDown(currentIndex: selectedIdx, visibleCount: total)
        TestHarness.assertEqual(selectedIdx, 0, "Down Arrow from bottom wraps circularly to top (index 0)")

        // 4. Quick Selection Keys (1..9)
        let allVisible = storage.pinnedItems + storage.recentItems
        let selected1 = ShortcutNavigator.targetItem(forShortcut: 1, in: allVisible)
        TestHarness.assertEqual(selected1?.id, allVisible[0].id, "Key '1' maps to first visible item")

        let selected5 = ShortcutNavigator.targetItem(forShortcut: 5, in: allVisible)
        TestHarness.assertEqual(selected5?.id, allVisible[4].id, "Key '5' maps to 5th visible item")

        let selected9 = ShortcutNavigator.targetItem(forShortcut: 9, in: allVisible)
        TestHarness.assertNil(selected9, "Key '9' returns nil when fewer than 9 items are visible")

        // Shortcut Index resolution
        TestHarness.assertEqual(ShortcutNavigator.shortcutIndex(for: allVisible[0], in: allVisible), 1, "Shortcut index for first item is 1")
        TestHarness.assertEqual(ShortcutNavigator.shortcutIndex(for: allVisible[4], in: allVisible), 5, "Shortcut index for 5th item is 5")

        // 5. Per-Row Pin / Unpin and Delete
        storage.togglePin(id: item1.id)
        TestHarness.assertFalse(storage.items.first(where: { $0.id == item1.id })?.isPinned ?? true, "item1 unpinned successfully")

        storage.deleteItem(id: item5.id)
        TestHarness.assertEqual(storage.items.count, 4, "Item count decremented to 4 after delete")
        TestHarness.assertNil(storage.items.first(where: { $0.id == item5.id }), "item5 deleted completely")
    }
}
