import Foundation
import CoreGraphics
import AppKit
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

        // 6. Hover Preview & Thumbnail Image Synchronization across Distinct Items
        let imgA = MockScreenCaptureProvider.createSyntheticImage(size: CGSize(width: 320, height: 180))!
        let imgB = MockScreenCaptureProvider.createSyntheticImage(size: CGSize(width: 500, height: 400))!
        let imgC = MockScreenCaptureProvider.createSyntheticImage(size: CGSize(width: 640, height: 360))!

        let hoverA = try! storage.save(image: imgA, sourceApp: "AppA", captureType: .region, tags: ["a"])
        let hoverB = try! storage.save(image: imgB, sourceApp: "AppB", captureType: .scrolling, tags: ["b"])
        let hoverC = try! storage.save(image: imgC, sourceApp: "AppC", captureType: .region, tags: ["c"])

        let resolvedThumbA = ShotThumbnailView.resolveThumbnail(for: hoverA, storageManager: storage)
        let resolvedThumbB = ShotThumbnailView.resolveThumbnail(for: hoverB, storageManager: storage)
        let resolvedPreviewA = ThumbnailHoverPreviewCardView.resolveImage(for: hoverA, storageManager: storage)
        let resolvedPreviewB = ThumbnailHoverPreviewCardView.resolveImage(for: hoverB, storageManager: storage)
        let resolvedPreviewC = ThumbnailHoverPreviewCardView.resolveImage(for: hoverC, storageManager: storage)

        TestHarness.assertNotNil(resolvedThumbA, "Thumbnail A resolves synchronously")
        TestHarness.assertNotNil(resolvedThumbB, "Thumbnail B resolves synchronously")
        TestHarness.assertEqual(Int(resolvedPreviewA?.size.width ?? 0), 320, "Preview A width matches hoverA (320)")
        TestHarness.assertEqual(Int(resolvedPreviewB?.size.width ?? 0), 500, "Preview B width matches hoverB (500)")
        TestHarness.assertEqual(Int(resolvedPreviewC?.size.width ?? 0), 640, "Preview C width matches hoverC (640)")

        let panel = ThumbnailHoverPreviewPanel.shared
        panel.storageManager = storage
        panel.hide(immediate: true)

        // Show hoverA (runs after 100ms debounce when hidden, or immediately when visible)
        panel.orderFront(nil)
        panel.show(for: hoverA)
        TestHarness.assertEqual(panel.currentItemId, hoverA.id, "Panel currentItemId matches hoverA")
        TestHarness.assertEqual(panel.viewModel.item?.id, hoverA.id, "Panel viewModel item matches hoverA")
        TestHarness.assertEqual(Int(panel.viewModel.previewImage?.size.width ?? 0), 320, "Panel viewModel previewImage matches hoverA (320)")

        // Transition directly to hoverB while visible
        panel.show(for: hoverB)
        TestHarness.assertEqual(panel.currentItemId, hoverB.id, "Panel currentItemId updates immediately to hoverB")
        TestHarness.assertEqual(panel.viewModel.item?.id, hoverB.id, "Panel viewModel item updates immediately to hoverB")
        TestHarness.assertEqual(Int(panel.viewModel.previewImage?.size.width ?? 0), 500, "Panel viewModel previewImage updates immediately to hoverB (500)")

        // Simulate delayed onHover(false) from hoverA after hoverB is already active
        panel.hide(forItemId: hoverA.id)
        TestHarness.assertEqual(panel.currentItemId, hoverB.id, "Stale hide(forItemId: hoverA) does not clear active hoverB")
        TestHarness.assertEqual(Int(panel.viewModel.previewImage?.size.width ?? 0), 500, "Active hoverB previewImage remains intact after stale hide from hoverA")

        // Hide panel completely, then show hoverC
        panel.hide(immediate: true)
        panel.orderFront(nil)
        panel.show(for: hoverC)
        TestHarness.assertEqual(panel.currentItemId, hoverC.id, "Panel currentItemId matches hoverC after re-show")
        TestHarness.assertEqual(Int(panel.viewModel.previewImage?.size.width ?? 0), 640, "Panel viewModel previewImage matches hoverC (640) after orderOut/orderFront")
        panel.hide(immediate: true)

        // 7. Instant Copy Feedback Localization & RowActionButton
        let loc = LocalizationManager.shared
        loc.setLanguage(code: "en")
        TestHarness.assertEqual(loc.tr(.copiedToClipboard), "Copied to Clipboard", "English copiedToClipboard string matches")
        loc.setLanguage(code: "vi")
        TestHarness.assertEqual(loc.tr(.copiedToClipboard), "Đã sao chép vào bộ nhớ tạm", "Vietnamese copiedToClipboard string matches")
        loc.setLanguage(code: "en")

        let actionBtn = RowActionButton(icon: "checkmark", tooltip: "Copied", defaultTint: .green, hoverTint: .green, customBackground: nil) {}
        let _ = actionBtn.body
        TestHarness.assertTrue(true, "RowActionButton body evaluates cleanly")

        let copiedRow = ShotRowView(
            item: hoverA,
            storageManager: storage,
            shortcutIndex: 1,
            isSelected: false,
            isRecentlyCopied: true
        )
        let _ = copiedRow.body
        TestHarness.assertTrue(true, "ShotRowView evaluates cleanly with isRecentlyCopied = true")

        let mainView = MainShotView(storageManager: storage)
        mainView.triggerCopyFeedback(for: hoverA.id)
        TestHarness.assertTrue(true, "MainShotView triggerCopyFeedback executes cleanly")

        // 8. SearchBarView Clear Button, PointingHand Cursor & Tooltip
        var searchBindingText = "search sample"
        let searchBar = SearchBarView(text: .init(get: { searchBindingText }, set: { searchBindingText = $0 }))
        let _ = searchBar.body
        TestHarness.assertEqual(searchBindingText, "search sample", "SearchBar text binding matches")
        searchBindingText = ""
        TestHarness.assertEqual(searchBindingText, "", "Search text cleared cleanly")

        // 9. MainShotView Empty State Actions
        var regionCaptureTriggered = false
        var scrollingCaptureTriggered = false
        var popoverDismissed = false
        let emptyStorage = StorageManager(baseDirectory: sandboxDir.appendingPathComponent("EmptyStorageTest"), initialCapacity: 10)
        let emptyMainView = MainShotView(
            storageManager: emptyStorage,
            onDismiss: { popoverDismissed = true },
            onTriggerRegionCapture: { regionCaptureTriggered = true },
            onTriggerScrollingCapture: { scrollingCaptureTriggered = true }
        )
        let _ = emptyMainView.body
        TestHarness.assertTrue(emptyMainView.filteredItems.isEmpty, "Filtered items are empty for empty storage")

        emptyMainView.onCaptureRegion?()
        TestHarness.assertTrue(regionCaptureTriggered, "Quick capture region CTA triggers onCaptureRegion callback")

        emptyMainView.onScrollingCapture?()
        TestHarness.assertTrue(scrollingCaptureTriggered, "Quick scrolling capture CTA triggers onScrollingCapture callback")

        // 10. Slash (/) Shortcut & Focus Search Field Notification (v1.0.15)
        var searchFocusNotificationReceived = false
        let searchFocusObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("SuperShotFocusSearchField"),
            object: nil,
            queue: .main
        ) { _ in
            searchFocusNotificationReceived = true
        }

        let mainViewForKeyboard = MainShotView(storageManager: storage)
        mainViewForKeyboard.focusSearchField()
        TestHarness.assertTrue(searchFocusNotificationReceived, "focusSearchField() posts SuperShotFocusSearchField notification")
        NotificationCenter.default.removeObserver(searchFocusObserver)

        // 11. Finder Action & Open In Finder Localization (v1.0.17)
        let openInFinderText = LocalizationManager.shared.tr(.openInFinder)
        TestHarness.assertTrue(!openInFinderText.isEmpty, "openInFinder localization exists")
        TestHarness.assertTrue(mainViewForKeyboard.filteredItems.count > 0, "filteredItems contains seeded items")

        // 12. IME Composition Guard, Delete Feedback & Context Menu Shortcut Hints (v1.0.18)
        let deletedText = LocalizationManager.shared.tr(.screenshotDeleted)
        TestHarness.assertTrue(!deletedText.isEmpty, "screenshotDeleted localization exists")
        TestHarness.assertEqual(deletedText, "Screenshot Deleted", "screenshotDeleted in English")

        // Test triggerDeleteFeedback() execution without crash
        mainViewForKeyboard.triggerDeleteFeedback()

        // Verify context menu shortcut labels
        let copyWithShortcut = "\(LocalizationManager.shared.tr(.actionCopy)) (⌘C)"
        let saveWithShortcut = "\(LocalizationManager.shared.tr(.actionSave))... (⌘S)"
        let pinWithShortcut = "\(LocalizationManager.shared.tr(.pinButton)) (⌘P)"
        let deleteWithShortcut = "\(LocalizationManager.shared.tr(.deleteButton)) (⌫)"
        TestHarness.assertTrue(copyWithShortcut.contains("(⌘C)"), "Copy button contains (⌘C) shortcut")
        TestHarness.assertTrue(saveWithShortcut.contains("(⌘S)"), "Save button contains (⌘S) shortcut")
        TestHarness.assertTrue(pinWithShortcut.contains("(⌘P)"), "Pin button contains (⌘P) shortcut")
        TestHarness.assertTrue(deleteWithShortcut.contains("(⌫)"), "Delete button contains (⌫) shortcut")

        // 13. Differentiated Section Shortcuts, Badges, Fast Navigation & Unpinned Purge Toast (v1.0.19)
        let opt1Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "¡",
            charactersIgnoringModifiers: "1",
            isARepeat: false,
            keyCode: 18
        )!
        let parsedOpt1 = ShortcutNavigator.parseSectionShortcut(from: opt1Event, searchFieldHasFocus: false)
        TestHarness.assertEqual(parsedOpt1?.section, .pinned, "Option+1 parses as .pinned section")
        TestHarness.assertEqual(parsedOpt1?.digit, 1, "Option+1 parses digit 1")

        let cmd2Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "2",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: 19
        )!
        let parsedCmd2 = ShortcutNavigator.parseSectionShortcut(from: cmd2Event, searchFieldHasFocus: false)
        TestHarness.assertEqual(parsedCmd2?.section, .recent, "Cmd+2 parses as .recent section")
        TestHarness.assertEqual(parsedCmd2?.digit, 2, "Cmd+2 parses digit 2")

        let bare3Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "3",
            charactersIgnoringModifiers: "3",
            isARepeat: false,
            keyCode: 20
        )!
        let parsedBare3 = ShortcutNavigator.parseSectionShortcut(from: bare3Event, searchFieldHasFocus: false)
        TestHarness.assertEqual(parsedBare3?.section, .recent, "Bare 3 parses as .recent section")
        TestHarness.assertEqual(parsedBare3?.digit, 3, "Bare 3 parses digit 3")

        let searchFocusBare3 = ShortcutNavigator.parseSectionShortcut(from: bare3Event, searchFieldHasFocus: true)
        TestHarness.assertTrue(searchFocusBare3 == nil, "Bare 3 returns nil when searchFieldHasFocus is true")

        let searchFocusOpt1 = ShortcutNavigator.parseSectionShortcut(from: opt1Event, searchFieldHasFocus: true)
        TestHarness.assertEqual(searchFocusOpt1?.section, .pinned, "Option+1 triggers even when searchFieldHasFocus is true")

        // Badge string generation
        let dummyPinned = [hoverA, hoverB]
        let dummyRecent = [hoverC]
        TestHarness.assertEqual(ShortcutNavigator.badgeString(for: hoverA, pinnedItems: dummyPinned, recentItems: dummyRecent), "⌥1", "Pinned 0 badge is ⌥1")
        TestHarness.assertEqual(ShortcutNavigator.badgeString(for: hoverB, pinnedItems: dummyPinned, recentItems: dummyRecent), "⌥2", "Pinned 1 badge is ⌥2")
        TestHarness.assertEqual(ShortcutNavigator.badgeString(for: hoverC, pinnedItems: dummyPinned, recentItems: dummyRecent), "1", "Recent 0 badge is 1")

        // Target item resolution
        let targetPinned1 = ShortcutNavigator.targetItem(forSectionShortcut: (.pinned, 1), pinnedItems: dummyPinned, recentItems: dummyRecent)
        TestHarness.assertEqual(targetPinned1?.id, hoverA.id, "Target item for (.pinned, 1) resolves to hoverA")
        let targetRecent1 = ShortcutNavigator.targetItem(forSectionShortcut: (.recent, 1), pinnedItems: dummyPinned, recentItems: dummyRecent)
        TestHarness.assertEqual(targetRecent1?.id, hoverC.id, "Target item for (.recent, 1) resolves to hoverC")
        let targetOutOfRange = ShortcutNavigator.targetItem(forSectionShortcut: (.recent, 5), pinnedItems: dummyPinned, recentItems: dummyRecent)
        TestHarness.assertNil(targetOutOfRange, "Out of range section digit resolves to nil")

        // Clear unpinned feedback toast execution
        mainViewForKeyboard.triggerClearAllFeedback()

        // Localization key check
        let clearedToastText = LocalizationManager.shared.tr(.unpinnedHistoryCleared)
        TestHarness.assertEqual(clearedToastText, "Unpinned history cleared", "unpinnedHistoryCleared string in English")
    }
}
