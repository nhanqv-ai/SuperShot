import Foundation
import SuperShotCore

/// Unit tests for AppLanguage, LocalizationManager, and multilingual coverage.
public struct LocalizationTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Localization & Multilingual Tests")

        // 1. AppLanguage cases and count check
        TestHarness.assertEqual(AppLanguage.allCases.count, 10, "10 cases in AppLanguage (system + 9 languages)")
        TestHarness.assertEqual(AppLanguage.system.displayName, "System Default", "System display name")
        TestHarness.assertEqual(AppLanguage.english.displayName, "English", "English display name")
        TestHarness.assertEqual(AppLanguage.vietnamese.displayName, "Tiếng Việt", "Vietnamese display name")
        TestHarness.assertEqual(AppLanguage.german.displayName, "Deutsch", "German display name")
        TestHarness.assertEqual(AppLanguage.french.displayName, "Français", "French display name")
        TestHarness.assertEqual(AppLanguage.spanish.displayName, "Español", "Spanish display name")
        TestHarness.assertEqual(AppLanguage.japanese.displayName, "日本語", "Japanese display name")
        TestHarness.assertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文", "Simplified Chinese display name")
        TestHarness.assertEqual(AppLanguage.traditionalChinese.displayName, "繁體中文", "Traditional Chinese display name")
        TestHarness.assertEqual(AppLanguage.korean.displayName, "한국어", "Korean display name")

        // 2. Dynamic runtime language switching
        let loc = LocalizationManager.shared

        // Vietnamese
        loc.setLanguage(.vietnamese)
        TestHarness.assertEqual(loc.effectiveLanguage, .vietnamese, "Effective language switches to Vietnamese")
        TestHarness.assertEqual(loc.tr(.searchPlaceholder), "Tìm kiếm ảnh chụp...", "Search placeholder translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.actionScrollCapture), "Chụp cuộn trang", "Scroll capture action translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.toolSelect), "Chọn / Di chuyển", "Select tool translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.toolRectangle), "Hình chữ nhật", "Rectangle tool translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.toolBlur), "Làm mờ / Điểm ảnh", "Blur tool translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.presetRed), "Đỏ", "Red preset translated to Vietnamese")

        // German
        loc.setLanguage(.german)
        TestHarness.assertEqual(loc.effectiveLanguage, .german, "Effective language switches to German")
        TestHarness.assertEqual(loc.tr(.toolRectangle), "Rechteck", "Rectangle tool translated to German")
        TestHarness.assertEqual(loc.tr(.actionScrollCapture), "Scroll-Aufnahme", "Scroll capture translated to German")

        // French
        loc.setLanguage(.french)
        TestHarness.assertEqual(loc.effectiveLanguage, .french, "Effective language switches to French")
        TestHarness.assertEqual(loc.tr(.toolHighlighter), "Surligneur", "Highlighter translated to French")

        // Spanish
        loc.setLanguage(.spanish)
        TestHarness.assertEqual(loc.effectiveLanguage, .spanish, "Effective language switches to Spanish")
        TestHarness.assertEqual(loc.tr(.toolArrow), "Flecha", "Arrow translated to Spanish")

        // Japanese
        loc.setLanguage(.japanese)
        TestHarness.assertEqual(loc.effectiveLanguage, .japanese, "Effective language switches to Japanese")
        TestHarness.assertEqual(loc.tr(.toolPen), "ペン", "Pen translated to Japanese")
        TestHarness.assertEqual(loc.tr(.emptyHistoryTitle), "スクリーンショットはまだありません", "Empty history translated to Japanese")

        // Simplified Chinese
        loc.setLanguage(.simplifiedChinese)
        TestHarness.assertEqual(loc.effectiveLanguage, .simplifiedChinese, "Effective language switches to Simplified Chinese")
        TestHarness.assertEqual(loc.tr(.pinnedSection), "已置顶", "Pinned section translated to Simplified Chinese")

        // Traditional Chinese
        loc.setLanguage(.traditionalChinese)
        TestHarness.assertEqual(loc.effectiveLanguage, .traditionalChinese, "Effective language switches to Traditional Chinese")
        TestHarness.assertEqual(loc.tr(.pinnedSection), "已置頂", "Pinned section translated to Traditional Chinese")

        // Korean
        loc.setLanguage(.korean)
        TestHarness.assertEqual(loc.effectiveLanguage, .korean, "Effective language switches to Korean")
        TestHarness.assertEqual(loc.tr(.toolText), "텍스트", "Text tool translated to Korean")

        // English
        loc.setLanguage(.english)
        TestHarness.assertEqual(loc.effectiveLanguage, .english, "Effective language switches to English")
        TestHarness.assertEqual(loc.tr(.searchPlaceholder), "Search screenshots...", "Search placeholder translated to English")
        TestHarness.assertEqual(loc.tr(.actionScrollCapture), "Scrolling Capture", "Scroll capture translated to English")

        // 3. Dynamic parameterized string formatting
        TestHarness.assertEqual(L10nKey.dimensionBadge(1920, 1080).localized(for: .english), "1920 x 1080 px", "Dimension badge formatting")
        TestHarness.assertEqual(L10nKey.itemCount(3, 10).localized(for: .vietnamese), "3 / 10", "Vietnamese item count")
        TestHarness.assertEqual(L10nKey.itemCount(3, 10).localized(for: .english), "3 of 10", "English item count")
        TestHarness.assertEqual(L10nKey.versionLabel("1.0.0").localized(for: .english), "Version 1.0.0", "Version label formatting")

        // 4. v1.0.9 Localization keys coverage across languages
        let v109Keys: [L10nKey] = [
            .permissionsSectionTitle,
            .filenamePreviewLabel,
            .clearSearchTooltip,
            .clearSearchButton,
            .quickCaptureRegion,
            .quickCaptureScroll,
            .welcomeTitle,
            .welcomeSubtitle,
            .getStartedButton,
            .welcomeGuideButton,
            .licenseLabel
        ]
        for key in v109Keys {
            for lang in AppLanguage.allCases {
                let text = key.localized(for: lang)
                TestHarness.assertFalse(text.isEmpty, "Key \(key) has non-empty translation in \(lang.rawValue)")
            }
        }

        // Spot-check English and Vietnamese for v1.0.9 keys
        loc.setLanguage(.english)
        TestHarness.assertEqual(loc.tr(.clearSearchButton), "Clear Search", "Clear Search button translated to English")
        TestHarness.assertEqual(loc.tr(.welcomeTitle), "Welcome to SuperShot", "Welcome title translated to English")
        TestHarness.assertEqual(loc.tr(.quickCaptureRegion), "Area Capture (⌥S)", "Area Capture shortcut translated to English")
        TestHarness.assertEqual(loc.tr(.quickCaptureScroll), "Scrolling Capture (⌥⇧S)", "Scrolling Capture shortcut translated to English")

        loc.setLanguage(.vietnamese)
        TestHarness.assertEqual(loc.tr(.clearSearchButton), "Xóa tìm kiếm", "Clear Search button translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.welcomeTitle), "Chào mừng đến với SuperShot", "Welcome title translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.quickCaptureRegion), "Chụp vùng màn hình (⌥S)", "Area Capture shortcut translated to Vietnamese")
        TestHarness.assertEqual(loc.tr(.quickCaptureScroll), "Chụp cuộn trang (⌥⇧S)", "Scrolling Capture shortcut translated to Vietnamese")

        // 5. v1.0.10 Localization keys coverage across 9 languages
        let v1010Keys: [L10nKey] = [
            .welcomeFeature1Title,
            .welcomeFeature1Desc,
            .welcomeFeature2Title,
            .welcomeFeature2Desc,
            .welcomeFeature3Title,
            .welcomeFeature3Desc,
            .zoomOutTooltip,
            .zoomActualSizeTooltip,
            .zoomInTooltip,
            .zoomFitWidthTooltip,
            .strokeWidthHUD(4),
            .resetShortcutTooltip("Option+S"),
            .previewCancelTooltip,
            .previewDoneTooltip
        ]
        for key in v1010Keys {
            for lang in AppLanguage.allCases {
                let text = key.localized(for: lang)
                TestHarness.assertFalse(text.isEmpty, "v1.0.10 Key \(key) has non-empty translation in \(lang.rawValue)")
            }
        }

        loc.setLanguage(.english)
        TestHarness.assertEqual(loc.tr(.welcomeFeature1Title), "In-Place Capture & Annotation (Option+S)", "Feature 1 title English")
        TestHarness.assertEqual(loc.tr(.zoomOutTooltip), "Zoom Out (⌘-)", "Zoom out tooltip English")
        TestHarness.assertEqual(loc.tr(.strokeWidthHUD(3)), "Stroke Width: 3 pt", "Stroke width HUD English")
        TestHarness.assertEqual(loc.tr(.resetShortcutTooltip("Option+S")), "Reset to Option+S", "Reset shortcut tooltip English")
        TestHarness.assertEqual(loc.tr(.previewCancelTooltip), "Cancel (Esc)", "Cancel tooltip English")
        TestHarness.assertEqual(loc.tr(.previewDoneTooltip), "Done (Return / Enter)", "Done tooltip English")

        loc.setLanguage(.vietnamese)
        TestHarness.assertEqual(loc.tr(.welcomeFeature1Title), "Chụp vùng & Chú thích tại chỗ (Option+S)", "Feature 1 title Vietnamese")
        TestHarness.assertEqual(loc.tr(.zoomOutTooltip), "Thu nhỏ (⌘-)", "Zoom out tooltip Vietnamese")
        TestHarness.assertEqual(loc.tr(.strokeWidthHUD(3)), "Độ dày nét: 3 pt", "Stroke width HUD Vietnamese")
        TestHarness.assertEqual(loc.tr(.resetShortcutTooltip("Option+S")), "Đặt lại về Option+S", "Reset shortcut tooltip Vietnamese")
        TestHarness.assertEqual(loc.tr(.previewCancelTooltip), "Hủy (Esc)", "Cancel tooltip Vietnamese")
        TestHarness.assertEqual(loc.tr(.previewDoneTooltip), "Hoàn thành (Return / Enter)", "Done tooltip Vietnamese")
        TestHarness.assertEqual(loc.tr(.layerBringToFront), "Chuyển lên trên cùng (⌘⇧])", "Layer bring to front Vietnamese")
        TestHarness.assertEqual(loc.tr(.layerSendToBack), "Chuyển xuống dưới cùng (⌘⇧[)", "Layer send to back Vietnamese")
        TestHarness.assertEqual(loc.tr(.layerBringForward), "Tiến lên một lớp (⌘])", "Layer bring forward Vietnamese")
        TestHarness.assertEqual(loc.tr(.layerSendBackward), "Lùi lại một lớp (⌘[)", "Layer send backward Vietnamese")
        TestHarness.assertEqual(loc.tr(.zoomHUD(125)), "Thu phóng: 125%", "Zoom HUD Vietnamese")
        TestHarness.assertEqual(loc.tr(.framesCount(8)), "8 khung hình", "Frames count Vietnamese")
        TestHarness.assertEqual(loc.tr(.screenshotDeleted), "Đã xóa ảnh chụp", "Screenshot deleted Vietnamese")
        TestHarness.assertEqual(loc.tr(.copiedDiagnostics), "Đã sao chép thông tin chẩn đoán", "Copied diagnostics Vietnamese")

        loc.setLanguage(.english)
        TestHarness.assertEqual(loc.tr(.framesCount(8)), "8 frames", "Frames count English")
        TestHarness.assertEqual(loc.tr(.screenshotDeleted), "Screenshot Deleted", "Screenshot deleted English")
        TestHarness.assertEqual(loc.tr(.copiedDiagnostics), "Diagnostic Info Copied", "Copied diagnostics English")

        let v1018Keys: [L10nKey] = [
            .framesCount(5),
            .screenshotDeleted,
            .copiedDiagnostics
        ]
        for key in v1018Keys {
            for lang in AppLanguage.allCases {
                let text = key.localized(for: lang)
                TestHarness.assertFalse(text.isEmpty, "v1.0.18 Key \(key) has non-empty translation in \(lang.rawValue)")
            }
        }

        let v1019Keys: [L10nKey] = [
            .rememberLabel,
            .unpinnedHistoryCleared
        ]
        for key in v1019Keys {
            for lang in AppLanguage.allCases {
                let text = key.localized(for: lang)
                TestHarness.assertFalse(text.isEmpty, "v1.0.19 Key \(key) has non-empty translation in \(lang.rawValue)")
            }
        }

        let v1020Keys: [L10nKey] = [
            .actionAnnotate,
            .saveTallScreenshotTitle,
            .tallScreenshotWindowTitle,
            .customColorPreset
        ]
        for key in v1020Keys {
            for lang in AppLanguage.allCases {
                let text = key.localized(for: lang)
                TestHarness.assertFalse(text.isEmpty, "v1.0.20 Key \(key) has non-empty translation in \(lang.rawValue)")
            }
        }

        let v1021Keys: [L10nKey] = [
            .hudUndo,
            .hudRedo,
            .hudDuplicate,
            .quickSelectHintWithPinned
        ]
        for key in v1021Keys {
            for lang in AppLanguage.allCases {
                let text = key.localized(for: lang)
                TestHarness.assertFalse(text.isEmpty, "v1.0.21 Key \(key) has non-empty translation in \(lang.rawValue)")
            }
        }

        // Specific translation verification for Vietnamese
        TestHarness.assertEqual(L10nKey.actionAnnotate.localized(for: .vietnamese), "Thêm chú thích...", "actionAnnotate translated to Vietnamese")
        TestHarness.assertEqual(L10nKey.saveTallScreenshotTitle.localized(for: .vietnamese), "Lưu ảnh chụp cuộn dài đã ghép", "saveTallScreenshotTitle translated to Vietnamese")
        TestHarness.assertEqual(L10nKey.tallScreenshotWindowTitle.localized(for: .vietnamese), "SuperShot — Ảnh chụp cuộn dài", "tallScreenshotWindowTitle translated to Vietnamese")
        TestHarness.assertEqual(L10nKey.customColorPreset.localized(for: .vietnamese), "Tự chọn", "customColorPreset translated to Vietnamese")
        TestHarness.assertEqual(L10nKey.hudUndo.localized(for: .vietnamese), "Hoàn tác (⌘Z)", "hudUndo translated to Vietnamese")
        TestHarness.assertEqual(L10nKey.hudRedo.localized(for: .vietnamese), "Làm lại (⌘⇧Z)", "hudRedo translated to Vietnamese")
        TestHarness.assertEqual(L10nKey.hudDuplicate.localized(for: .vietnamese), "Đã nhân bản (⌘D)", "hudDuplicate translated to Vietnamese")
        TestHarness.assertEqual(L10nKey.quickSelectHintWithPinned.localized(for: .vietnamese), "⌥1-9: Đã ghim · 1-9: Gần đây", "quickSelectHintWithPinned translated to Vietnamese")

        // 6. Zero emoji invariant check across all keys in all languages
        validateZeroEmojisAcrossDictionary()

        // 7. Reset to system
        loc.setLanguage(.system)
        TestHarness.assertEqual(loc.currentLanguage, .system, "Reset language to system")
    }

    private static func validateZeroEmojisAcrossDictionary() {
        let testKeys: [L10nKey] = [
            .appTitle, .searchPlaceholder, .preferencesTooltip, .dismissTooltip,
            .toolSelect, .toolRectangle, .toolEllipse, .toolArrow, .toolLine,
            .toolPen, .toolHighlighter, .toolText, .toolBlur, .actionScrollCapture,
            .actionCopy, .actionSave, .pinnedSection, .recentSection, .tabGeneral,
            .tabCaptureSave, .tabHistory, .tabAbout, .presetRed, .presetGreen,
            .permissionsSectionTitle, .filenamePreviewLabel, .clearSearchTooltip,
            .clearSearchButton, .quickCaptureRegion, .quickCaptureScroll,
            .welcomeTitle, .welcomeSubtitle, .getStartedButton, .welcomeGuideButton,
            .licenseLabel,
            .welcomeFeature1Title, .welcomeFeature1Desc,
            .welcomeFeature2Title, .welcomeFeature2Desc,
            .welcomeFeature3Title, .welcomeFeature3Desc,
            .zoomOutTooltip, .zoomActualSizeTooltip,
            .zoomInTooltip, .zoomFitWidthTooltip,
            .strokeWidthHUD(4), .resetShortcutTooltip("Option+S"),
            .previewCancelTooltip, .previewDoneTooltip,
            .layerBringToFront, .layerSendToBack, .layerBringForward, .layerSendBackward,
            .zoomHUD(125), .captureOverlayInstruction, .directAutoPaste,
            .framesCount(10), .screenshotDeleted, .copiedDiagnostics,
            .rememberLabel, .unpinnedHistoryCleared,
            .actionAnnotate, .saveTallScreenshotTitle, .tallScreenshotWindowTitle, .customColorPreset,
            .hudUndo, .hudRedo, .hudDuplicate, .quickSelectHintWithPinned
        ]

        let emojiRanges: [ClosedRange<UInt32>] = [
            0x1F300...0x1FAFF, // Misc Symbols & Pictographs
            0x2600...0x27BF,   // Dingbats & Symbols
            0x1F1E6...0x1F1FF  // Flags
        ]

        for key in testKeys {
            for lang in AppLanguage.allCases {
                let string = key.localized(for: lang)
                for scalar in string.unicodeScalars {
                    let val = scalar.value
                    var isEmoji = false
                    for range in emojiRanges {
                        if range.contains(val) { isEmoji = true; break }
                    }
                    if !isEmoji && (val == 0xFE0E || val == 0xFE0F) {
                        isEmoji = true
                    }
                    TestHarness.assertFalse(isEmoji, "Key \(key) in \(lang.rawValue) contains zero emojis")
                }
            }
        }
    }
}
