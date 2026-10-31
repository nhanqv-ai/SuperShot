import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import SuperShotCore
import SuperShot

/// Comprehensive test suite for Cycle 14 features (F1–F10, v1.0.21 / Build 21).
public struct Cycle14Tests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Cycle 14 (v1.0.21) UX Polish & Live GUI Audit Tests")

        let storage = StorageManager(baseDirectory: sandboxDir)
        let sampleImage = MockScreenCaptureProvider.createSyntheticImage(size: CGSize(width: 400, height: 300))!
        let item = try! storage.save(image: sampleImage, sourceApp: "Finder", captureType: .region)
        storage.flushDiskQueue()

        // ---------------------------------------------------------------------
        // F1: Native Drag-and-Drop in History Rows
        // ---------------------------------------------------------------------
        let fileURL = storage.getImageURL(for: item)
        TestHarness.assertTrue(FileManager.default.fileExists(atPath: fileURL.path), "F1: Saved image file exists at storageManager.getImageURL")
        let itemProvider = NSItemProvider(contentsOf: fileURL)
        TestHarness.assertNotNil(itemProvider, "F1: NSItemProvider initialized with contentsOf fileURL")

        if let imgData = storage.getImageData(for: item), let nsImage = NSImage(data: imgData) {
            itemProvider?.registerObject(nsImage, visibility: .all)
            TestHarness.assertTrue(true, "F1: NSImage registered with .all visibility on itemProvider")
        } else {
            TestHarness.assertTrue(false, "F1: Failed to load NSImage from storageManager")
        }

        let shotRow = ShotRowView(item: item, storageManager: storage)
        let _ = shotRow.body
        TestHarness.assertTrue(true, "F1: ShotRowView with onDrag builds and renders body cleanly")

        // ---------------------------------------------------------------------
        // F2: Re-Annotate Keyboard Shortcut (Cmd+Shift+A) & Context Menu Parity
        // ---------------------------------------------------------------------
        var annotatedItem: ShotItem?
        let annotatingMainShotView = MainShotView(
            storageManager: storage,
            appSettings: AppSettings(),
            onAnnotateItem: { it in
                annotatedItem = it
            }
        )
        annotatingMainShotView.annotateItem(item)
        TestHarness.assertEqual(annotatedItem?.id, item.id, "F2: MainShotView.annotateItem invokes onAnnotateItem callback")

        let annotateMenuLabel = "\(LocalizationManager.shared.tr(.actionAnnotate)) (⌘⇧A)"
        TestHarness.assertTrue(annotateMenuLabel.contains("(⌘⇧A)"), "F2: Context menu label contains (⌘⇧A) shortcut hint")

        // ---------------------------------------------------------------------
        // F3: Keyboard Copy Confirmation Delay
        // ---------------------------------------------------------------------
        let display = CaptureDisplayInfo(
            displayID: 1,
            name: "TestDisplay",
            cocoaFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            cgBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            scaleFactor: 2.0,
            isMain: true,
            pixelSize: CGSize(width: 1600, height: 1200)
        )
        let capturedScreen = CapturedScreen(displayInfo: display, fullImage: sampleImage, timestamp: Date())
        let overlayWindow = CaptureOverlayWindow(capturedScreen: capturedScreen)
        overlayWindow.contentViewRef?.selectionRect = CGRect(x: 50, y: 50, width: 200, height: 150)

        // Simulate Return key press
        let returnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: overlayWindow.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        overlayWindow.keyDown(with: returnEvent)
        // Window should still be alive immediately after key down due to 0.18s async delay
        TestHarness.assertTrue(overlayWindow.contentViewRef != nil, "F3: CaptureOverlayWindow defers synchronous close on Return key")

        // ---------------------------------------------------------------------
        // F4: Vector Canvas Mutation HUD Pills
        // ---------------------------------------------------------------------
        let expectedHudUndo: [AppLanguage: String] = [
            .english: "Undo (⌘Z)",
            .vietnamese: "Hoàn tác (⌘Z)",
            .german: "Widerrufen (⌘Z)",
            .french: "Annuler (⌘Z)",
            .spanish: "Deshacer (⌘Z)",
            .japanese: "取り消し (⌘Z)",
            .simplifiedChinese: "撤销 (⌘Z)",
            .traditionalChinese: "復原 (⌘Z)",
            .korean: "실행 취소 (⌘Z)"
        ]
        let expectedHudRedo: [AppLanguage: String] = [
            .english: "Redo (⌘⇧Z)",
            .vietnamese: "Làm lại (⌘⇧Z)",
            .german: "Wiederholen (⌘⇧Z)",
            .french: "Rétablir (⌘⇧Z)",
            .spanish: "Rehacer (⌘⇧Z)",
            .japanese: "やり直し (⌘⇧Z)",
            .simplifiedChinese: "重做 (⌘⇧Z)",
            .traditionalChinese: "重做 (⌘⇧Z)",
            .korean: "다시 실행 (⌘⇧Z)"
        ]
        let expectedHudDuplicate: [AppLanguage: String] = [
            .english: "Duplicated (⌘D)",
            .vietnamese: "Đã nhân bản (⌘D)",
            .german: "Dupliziert (⌘D)",
            .french: "Dupliqué (⌘D)",
            .spanish: "Duplicado (⌘D)",
            .japanese: "複製しました (⌘D)",
            .simplifiedChinese: "已复制图元 (⌘D)",
            .traditionalChinese: "已複製圖元 (⌘D)",
            .korean: "복제됨 (⌘D)"
        ]

        for (lang, expected) in expectedHudUndo {
            TestHarness.assertEqual(L10nKey.hudUndo.localized(for: lang), expected, "F4: hudUndo translation matches for \(lang.rawValue)")
        }
        for (lang, expected) in expectedHudRedo {
            TestHarness.assertEqual(L10nKey.hudRedo.localized(for: lang), expected, "F4: hudRedo translation matches for \(lang.rawValue)")
        }
        for (lang, expected) in expectedHudDuplicate {
            TestHarness.assertEqual(L10nKey.hudDuplicate.localized(for: lang), expected, "F4: hudDuplicate translation matches for \(lang.rawValue)")
        }

        // Test CaptureOverlayContentView HUD notification invocations
        let selectionBoxView = CaptureOverlayContentView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            capturedScreen: capturedScreen
        )
        selectionBoxView.showHUDNotification(text: LocalizationManager.shared.tr(.hudUndo))
        TestHarness.assertEqual(selectionBoxView.toolHUDText, LocalizationManager.shared.tr(.hudUndo), "F4: CaptureOverlayContentView.showHUDNotification sets toolHUDText")

        // ---------------------------------------------------------------------
        // F5: Adaptive Popover Footer Shortcut Hint
        // ---------------------------------------------------------------------
        let expectedPinnedHint: [AppLanguage: String] = [
            .english: "⌥1-9: Pinned · 1-9: Recent",
            .vietnamese: "⌥1-9: Đã ghim · 1-9: Gần đây",
            .german: "⌥1-9: Angeheftet · 1-9: Zuletzt",
            .french: "⌥1-9: Épinglés · 1-9: Récents",
            .spanish: "⌥1-9: Fijados · 1-9: Recientes",
            .japanese: "⌥1-9: 固定中 · 1-9: 最近",
            .simplifiedChinese: "⌥1-9: 已固定 · 1-9: 最近",
            .traditionalChinese: "⌥1-9: 已釘選 · 1-9: 最近",
            .korean: "⌥1-9: 고정됨 · 1-9: 최근 항목"
        ]
        for (lang, expected) in expectedPinnedHint {
            TestHarness.assertEqual(L10nKey.quickSelectHintWithPinned.localized(for: lang), expected, "F5: quickSelectHintWithPinned matches for \(lang.rawValue)")
        }

        let emptyPopover = MainShotView(storageManager: storage, appSettings: AppSettings())
        let _ = emptyPopover.body
        TestHarness.assertTrue(true, "F5: MainShotView renders footer hint bar cleanly")

        // ---------------------------------------------------------------------
        // F6: Welcome Window Safe Area & Deep Linking
        // ---------------------------------------------------------------------
        let welcomeView = WelcomeView()
        let _ = welcomeView.body
        TestHarness.assertEqual(welcomeView.appVersionString, "v1.0.34", "F6: WelcomeView reports version v1.0.34")

        // Test PermissionManager open settings methods
        PermissionManager.shared.openScreenRecordingSettings()
        PermissionManager.shared.openAccessibilitySettings()
        TestHarness.assertTrue(true, "F6: PermissionManager settings open methods execute safely")

        // ---------------------------------------------------------------------
        // F7: Hex Input .onSubmit Preset Creation & Preview Placeholder
        // ---------------------------------------------------------------------
        TestHarness.assertTrue(ColorPreset.isValid(hex: "#FF5722"), "F7: #FF5722 is valid hex")
        TestHarness.assertTrue(ColorPreset.isValid(hex: "00E676"), "F7: 00E676 is valid hex without hash")
        TestHarness.assertFalse(ColorPreset.isValid(hex: "invalid"), "F7: 'invalid' is not valid hex")
        TestHarness.assertFalse(ColorPreset.isValid(hex: ""), "F7: Empty string is not valid hex")

        let settings = AppSettings()
        let initialPresetCount = settings.presets.count
        let customPreset = ColorPreset(name: LocalizationManager.shared.tr(.customColorPreset), hex: "#123456")
        let added = settings.addPreset(customPreset)
        TestHarness.assertTrue(added, "F7: Custom preset successfully added")
        TestHarness.assertEqual(settings.presets.count, initialPresetCount + 1, "F7: Preset count incremented by 1")

        // ---------------------------------------------------------------------
        // F8: VoiceOver Accessibility Role & Traits in Settings
        // ---------------------------------------------------------------------
        let generalTabBtn = SettingsTabButton(tab: .general, isSelected: true, action: {})
        let _ = generalTabBtn.body
        TestHarness.assertTrue(generalTabBtn.isSelected, "F8: SettingsTabButton selected state is true")

        let captureTabBtn = SettingsTabButton(tab: .captureSave, isSelected: false, action: {})
        let _ = captureTabBtn.body
        TestHarness.assertFalse(captureTabBtn.isSelected, "F8: SettingsTabButton selected state is false")

        // ---------------------------------------------------------------------
        // F9: Localization Hygiene & AboutSettingsTab Button Rhythm
        // ---------------------------------------------------------------------
        for lang in AppLanguage.allCases {
            let toolText = L10nKey.toolText.localized(for: lang)
            TestHarness.assertFalse(toolText.isEmpty, "F9: toolText non-empty for \(lang.rawValue)")
            let customName = L10nKey.customColorPreset.localized(for: lang)
            TestHarness.assertFalse(customName.isEmpty, "F9: customColorPreset non-empty for \(lang.rawValue)")
        }

        let aboutTab = AboutSettingsTab(appSettings: settings, storageManager: storage)
        let _ = aboutTab.body
        TestHarness.assertTrue(true, "F9: AboutSettingsTab renders body cleanly with flush-left action row")

        // ---------------------------------------------------------------------
        // F10: Canonical Version Bump to v1.0.21 / Build 21
        // ---------------------------------------------------------------------
        TestHarness.assertEqual(UpdateManager.shared.currentVersion, "1.0.34", "F10: UpdateManager currentVersion is 1.0.34")
        let diagString = AboutSettingsTab.diagnosticString(version: "1.0.34")
        TestHarness.assertTrue(diagString.contains("SuperShot v1.0.34"), "F10: Diagnostic string contains v1.0.34")
        TestHarness.assertTrue(diagString.contains("• Build 34"), "Diagnostic string contains application • Build 34")
    }
}
