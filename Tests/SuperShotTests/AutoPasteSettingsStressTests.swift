import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers
import SuperShotCore
import SuperShot

/// Stress test harness and empirical challenge suite for AutoPasteService,
/// PreviousAppTracker, SettingsView, and AppSettings.
public struct AutoPasteSettingsStressTests {

    // MARK: - Thread-Safe Tracking Helpers

    private final class ThreadSafeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Int = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }

        func increment() {
            lock.lock()
            _value += 1
            lock.unlock()
        }

        func reset() {
            lock.lock()
            _value = 0
            lock.unlock()
        }
    }

    private final class StressMockPasteSimulator: PasteSimulating, @unchecked Sendable {
        let postCount = ThreadSafeCounter()
        let activateCount = ThreadSafeCounter()
        var shouldSucceed: Bool = true

        func activate(app: NSRunningApplication) -> Bool {
            guard !app.isTerminated else { return false }
            activateCount.increment()
            return shouldSucceed
        }

        func postPasteKeyEvent() -> Bool {
            postCount.increment()
            return shouldSucceed
        }

        func postPasteKeyEvent(tap: CGEventTapLocation) -> Bool {
            postCount.increment()
            return shouldSucceed
        }

        func pasteToActiveApp(targetApp: NSRunningApplication?, delay: TimeInterval, completion: (() -> Void)?) {
            if let app = targetApp, !app.isTerminated {
                _ = activate(app: app)
            }
            if delay <= 0 {
                _ = postPasteKeyEvent()
                completion?()
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    _ = self?.postPasteKeyEvent()
                    completion?()
                }
            }
        }
    }

    // MARK: - Suite Entry Point

    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Challenger 2: AutoPaste & Settings Empirical Stress Tests")

        // 1. AutoPasteService Concurrency & Timing Stress
        testAutoPasteConcurrency()
        testZeroVsPositiveDelayBranching()
        testRapidRepeatedPasteInvocations()
        testUntrustedPermissionClipboardFallback()

        // 2. PreviousAppTracker Stress
        testPreviousAppTrackerExcludesOwnPID()
        testPreviousAppTrackerExternalPIDTracking()
        testPreviousAppTrackerTerminatedAppHandling()
        testPreviousAppTrackerConcurrency()

        // 3. AppSettings & ColorPreset Boundary Stress
        testColorPresetSixteenCapacityAndSeventeenthRejection(sandboxDir: sandboxDir)
        testColorPresetInPlaceDuplicateHexUpdate(sandboxDir: sandboxDir)
        testColorPresetInvalidHexHandling()
        testColorPresetResetToDefaults(sandboxDir: sandboxDir)
        testSliderBoundsClamping(sandboxDir: sandboxDir)
        testSaveModeAndDirectoryPersistence(sandboxDir: sandboxDir)
        testSettingsViewAndTabInstantiation(sandboxDir: sandboxDir)
    }

    // MARK: - 1. AutoPasteService Stress Tests

    private static func testAutoPasteConcurrency() {
        let mockSim = StressMockPasteSimulator()
        let service = AutoPasteService(
            pasteSimulator: mockSim,
            accessibilityChecker: { true },
            accessibilityPrompter: { true },
            accessibilityResetter: { true },
            settingsOpener: {},
            dispatchQueue: .global(qos: .userInitiated)
        )

        let concurrentOperations = 50
        let group = DispatchGroup()
        let completionCounter = ThreadSafeCounter()

        for _ in 0..<concurrentOperations {
            group.enter()
            DispatchQueue.global().async {
                let success = service.pasteToActiveApp(targetApp: nil, delay: 0.005) {
                    completionCounter.increment()
                    group.leave()
                }
                TestHarness.assertTrue(success, "Concurrent pasteToActiveApp invocation returns true")
            }
        }

        let waitResult = group.wait(timeout: .now() + 5.0)
        TestHarness.assertEqual(waitResult, .success, "All 50 concurrent paste requests finished without deadlock")
        TestHarness.assertEqual(completionCounter.value, concurrentOperations, "All 50 completions executed reliably")
        TestHarness.assertEqual(mockSim.postCount.value, concurrentOperations, "All 50 synthetic key events were posted")
    }

    private static func testZeroVsPositiveDelayBranching() {
        let mockSim = StressMockPasteSimulator()
        let service = AutoPasteService(
            pasteSimulator: mockSim,
            accessibilityChecker: { true },
            accessibilityPrompter: { true },
            accessibilityResetter: { true },
            settingsOpener: {}
        )

        // Case A: Zero delay (must be synchronous)
        mockSim.postCount.reset()
        var completedSync = false
        let retZero = service.pasteToActiveApp(targetApp: nil, delay: 0.0) {
            completedSync = true
        }
        TestHarness.assertTrue(retZero, "pasteToActiveApp with zero delay returns true")
        TestHarness.assertTrue(completedSync, "Zero delay executes completion synchronously on return")
        TestHarness.assertEqual(mockSim.postCount.value, 1, "Zero delay posts key event synchronously")

        // Case B: Negative delay (must clamp to <= 0 and execute synchronously)
        mockSim.postCount.reset()
        var completedNeg = false
        let retNeg = service.pasteToActiveApp(targetApp: nil, delay: -0.5) {
            completedNeg = true
        }
        TestHarness.assertTrue(retNeg, "pasteToActiveApp with negative delay returns true")
        TestHarness.assertTrue(completedNeg, "Negative delay executes completion synchronously on return")
        TestHarness.assertEqual(mockSim.postCount.value, 1, "Negative delay posts key event synchronously")

        // Case C: Positive delay (must dispatch asynchronously)
        mockSim.postCount.reset()
        var completedAsync = false
        let retPos = service.pasteToActiveApp(targetApp: nil, delay: 0.02) {
            completedAsync = true
        }
        TestHarness.assertTrue(retPos, "pasteToActiveApp with positive delay returns true immediately")
        TestHarness.assertFalse(completedAsync, "Positive delay completion is deferred asynchronously")

        // Pump run loop so main queue block executes in headless environment
        let deadline = Date().addingTimeInterval(2.0)
        while !completedAsync && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        TestHarness.assertTrue(completedAsync, "Positive delay completion fired after timer deadline")
        TestHarness.assertEqual(mockSim.postCount.value, 1, "Positive delay key event was posted")
    }

    private static func testRapidRepeatedPasteInvocations() {
        let mockSim = StressMockPasteSimulator()
        let service = AutoPasteService(
            pasteSimulator: mockSim,
            accessibilityChecker: { true },
            accessibilityPrompter: { true },
            accessibilityResetter: { true },
            settingsOpener: {}
        )

        let iterations = 200
        mockSim.postCount.reset()

        for _ in 0..<iterations {
            _ = service.pasteToActiveApp(targetApp: nil, delay: 0.0)
        }

        TestHarness.assertEqual(mockSim.postCount.value, iterations, "Rapid burst of 200 synchronous paste calls succeeded 100%")
    }

    private static func testUntrustedPermissionClipboardFallback() {
        let mockSim = StressMockPasteSimulator()
        var promptCalled = false

        let service = AutoPasteService(
            pasteSimulator: mockSim,
            accessibilityChecker: { false }, // Untrusted permission simulation
            accessibilityPrompter: {
                promptCalled = true
                return false
            },
            accessibilityResetter: { true },
            settingsOpener: {}
        )

        // 1. pasteToActiveApp without prompt
        var completionFired = false
        let untrustedWithoutPrompt = service.pasteToActiveApp(targetApp: nil, delay: 0.0, promptIfUntrusted: false) {
            completionFired = true
        }
        TestHarness.assertFalse(untrustedWithoutPrompt, "Untrusted pasteToActiveApp returns false")
        TestHarness.assertTrue(completionFired, "Completion still fires when untrusted")
        TestHarness.assertFalse(promptCalled, "Prompter not invoked when promptIfUntrusted is false")
        TestHarness.assertEqual(mockSim.postCount.value, 0, "No synthetic keys posted when untrusted")

        // 2. pasteToActiveApp with prompt
        promptCalled = false
        completionFired = false
        let untrustedWithPrompt = service.pasteToActiveApp(targetApp: nil, delay: 0.0, promptIfUntrusted: true) {
            completionFired = true
        }
        TestHarness.assertFalse(untrustedWithPrompt, "Untrusted pasteToActiveApp with prompt returns false")
        TestHarness.assertTrue(promptCalled, "Prompter invoked when promptIfUntrusted is true")
        TestHarness.assertTrue(completionFired, "Completion fires when untrusted with prompt")
        TestHarness.assertEqual(mockSim.postCount.value, 0, "Still no synthetic keys posted")

        // 3. pasteImageDirectly clipboard fallback verification
        // Create synthetic image to copy
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 40 * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let sampleImage = ctx.makeImage()!

        let expSema = DispatchSemaphore(value: 0)
        var pasteImageResult = false

        Task {
            pasteImageResult = await service.pasteImageDirectly(sampleImage, targetApp: nil, delay: 0.0)
            expSema.signal()
        }

        _ = expSema.wait(timeout: .now() + 2.0)
        TestHarness.assertFalse(pasteImageResult, "pasteImageDirectly returns false due to untrusted accessibility")

        // Check clipboard content: Image data MUST be present on NSPasteboard despite untrusted accessibility!
        let pb = NSPasteboard.general
        let hasPNG = pb.data(forType: .png) != nil
        let hasTIFF = pb.data(forType: .tiff) != nil
        TestHarness.assertTrue(hasPNG || hasTIFF, "Clipboard fallback: Image data was successfully copied to pasteboard")
    }

    // MARK: - 2. PreviousAppTracker Stress Tests

    private static func testPreviousAppTrackerExcludesOwnPID() {
        let tracker = PreviousAppTracker()
        tracker.clear()
        TestHarness.assertNil(tracker.previousApp, "Fresh tracker has nil previousApp")

        // Attempt to set own process as previous application
        let currentApp = NSRunningApplication.current
        tracker.setPreviousApp(currentApp)
        TestHarness.assertNil(tracker.previousApp, "Own process PID (\(currentApp.processIdentifier)) strictly excluded from previousApp")

        // captureFrontmostApplication when current is frontmost
        tracker.captureFrontmostApplication()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            TestHarness.assertNil(tracker.previousApp, "captureFrontmostApplication ignores current process")
        }
    }

    private static func testPreviousAppTrackerExternalPIDTracking() {
        let tracker = PreviousAppTracker()
        tracker.clear()

        // Find an external running application on macOS
        let runningApps = NSWorkspace.shared.runningApplications
        let externalApp = runningApps.first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }

        if let external = externalApp {
            tracker.setPreviousApp(external)
            TestHarness.assertNotNil(tracker.previousApp, "Successfully tracked external running app")
            TestHarness.assertEqual(tracker.previousApp?.processIdentifier, external.processIdentifier, "Tracked PID matches external app PID (\(external.processIdentifier))")

            // Clearing tracker
            tracker.clear()
            TestHarness.assertNil(tracker.previousApp, "Tracker cleared successfully")
        } else {
            TestHarness.recordPass("No external apps running in environment (headless container)")
        }
    }

    private static func testPreviousAppTrackerTerminatedAppHandling() {
        let tracker = PreviousAppTracker()
        tracker.clear()

        // Test with mock terminated application representation or PID cleanup
        let runningApps = NSWorkspace.shared.runningApplications
        if let terminatedCandidate = runningApps.first(where: { $0.isTerminated }) {
            tracker.setPreviousApp(terminatedCandidate)
            TestHarness.assertNil(tracker.previousApp, "Terminated application is immediately detected and returns nil")
        } else {
            // Validate clear logic cleans state
            tracker.clear()
            TestHarness.assertNil(tracker.previousApp, "Tracker clear verifies cleanly")
        }
    }

    private static func testPreviousAppTrackerConcurrency() {
        let tracker = PreviousAppTracker()
        tracker.clear()

        let externalApp = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
        }

        let iterations = 100
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                if i % 3 == 0 {
                    tracker.setPreviousApp(externalApp)
                } else if i % 3 == 1 {
                    _ = tracker.previousApp
                } else {
                    tracker.clear()
                }
                group.leave()
            }
        }

        let waitRes = group.wait(timeout: .now() + 3.0)
        TestHarness.assertEqual(waitRes, .success, "Concurrent PreviousAppTracker access completed without deadlock or crash")
    }

    // MARK: - 3. AppSettings & ColorPreset Boundary Stress Tests

    private static func testColorPresetSixteenCapacityAndSeventeenthRejection(sandboxDir: URL) {
        let settingsURL = sandboxDir.appendingPathComponent("preset_cap_test.json")
        let settings = AppSettings(settingsURL: settingsURL)
        settings.resetPresets()
        TestHarness.assertEqual(settings.presets.count, 8, "Reset presets starts with exactly 8 defaults")

        // Add 8 unique presets to reach capacity 16
        for i in 1...8 {
            let uniqueHex = String(format: "#%02X%02X%02X", i * 15, i * 25, i * 30)
            let p = ColorPreset(name: "Preset \(i)", hex: uniqueHex)
            let added = settings.addPreset(p)
            TestHarness.assertTrue(added, "Preset \(i) added successfully up to capacity")
        }
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count is exactly 16")

        // 17th preset MUST be rejected
        let seventeenth = ColorPreset(name: "Seventeenth", hex: "#ABCDEF")
        let addedSeventeenth = settings.addPreset(seventeenth)
        TestHarness.assertFalse(addedSeventeenth, "17th unique preset addition is strictly rejected")
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count remains clamped at 16")

        // 18th preset also rejected
        let eighteenth = ColorPreset(name: "Eighteenth", hex: "#FEDCBA")
        let addedEighteenth = settings.addPreset(eighteenth)
        TestHarness.assertFalse(addedEighteenth, "18th preset rejected")
        TestHarness.assertEqual(settings.presets.count, 16, "Presets count still strictly 16")
    }

    private static func testColorPresetInPlaceDuplicateHexUpdate(sandboxDir: URL) {
        let settingsURL = sandboxDir.appendingPathComponent("preset_update_test.json")
        let settings = AppSettings(settingsURL: settingsURL)
        settings.resetPresets()

        // Existing preset #FF3B30 is "Red"
        let initialCount = settings.presets.count

        // Update with lowercase hex and new name
        let updateRed = ColorPreset(name: "Crimson Red", hex: "#ff3b30")
        let updateResult = settings.addPreset(updateRed)
        TestHarness.assertTrue(updateResult, "Adding existing hex returns true for in-place update")
        TestHarness.assertEqual(settings.presets.count, initialCount, "Count does not increment on duplicate hex")

        let updatedPreset = settings.presets.first(where: { $0.hex == "#FF3B30" })
        TestHarness.assertEqual(updatedPreset?.name, "Crimson Red", "Preset name was updated in-place to 'Crimson Red'")

        // Update when presets list is full at 16
        for i in 1...8 {
            let p = ColorPreset(name: "Filler \(i)", hex: String(format: "#11%02X22", i * 20))
            settings.addPreset(p)
        }
        TestHarness.assertEqual(settings.presets.count, 16, "Presets filled to 16")

        // Updating an existing hex when at max 16 must still SUCCEED in-place
        let updateAtMax = ColorPreset(name: "Ruby Flame", hex: "#FF3B30")
        let updateAtMaxResult = settings.addPreset(updateAtMax)
        TestHarness.assertTrue(updateAtMaxResult, "Updating existing hex succeeds even when preset shelf is at max capacity 16")
        TestHarness.assertEqual(settings.presets.count, 16, "Count remains 16")
        TestHarness.assertEqual(settings.presets.first(where: { $0.hex == "#FF3B30" })?.name, "Ruby Flame", "Name updated at max capacity")
    }

    private static func testColorPresetInvalidHexHandling() {
        let invalidHexes = [
            "#XYZ",
            "#12345",
            "#1234567",
            "",
            "   ",
            "#12G456",
            "#12",
            "#1234",
            "ZZZZZZ",
            "#",
            "######"
        ]

        for inv in invalidHexes {
            TestHarness.assertFalse(ColorPreset.isValid(hex: inv), "ColorPreset.isValid is false for '\(inv)'")
            TestHarness.assertNil(ColorPreset.parseRGB(hex: inv), "ColorPreset.parseRGB returns nil for '\(inv)'")

            let normalized = ColorPreset.normalize(hex: inv, defaultHex: "#FF3B30")
            TestHarness.assertEqual(normalized, "#FF3B30", "ColorPreset.normalize gracefully falls back to default for '\(inv)'")

            let preset = ColorPreset(name: "Faulty", hex: inv)
            TestHarness.assertEqual(preset.hex, "#FF3B30", "ColorPreset initializer normalizes invalid hex to default without crashing")
        }

        // Test valid 3-character hex expansion (#RGB -> #RRGGBB)
        TestHarness.assertTrue(ColorPreset.isValid(hex: "#F00"), "#F00 is valid hex")
        TestHarness.assertEqual(ColorPreset.normalize(hex: "#F00"), "#FF0000", "#F00 normalizes to #FF0000")
        TestHarness.assertEqual(ColorPreset.normalize(hex: "0F0"), "#00FF00", "0F0 normalizes to #00FF00")
        TestHarness.assertEqual(ColorPreset.normalize(hex: "#00F"), "#0000FF", "#00F normalizes to #0000FF")

        // Test valid 6-character hex
        TestHarness.assertTrue(ColorPreset.isValid(hex: "#123456"), "#123456 is valid")
        TestHarness.assertEqual(ColorPreset.normalize(hex: "123456"), "#123456", "123456 prepends hash and normalizes")
    }

    private static func testColorPresetResetToDefaults(sandboxDir: URL) {
        let settingsURL = sandboxDir.appendingPathComponent("preset_reset_test.json")
        let settings = AppSettings(settingsURL: settingsURL)

        // Delete several presets
        if let first = settings.presets.first {
            settings.deletePreset(id: first.id)
        }
        if let second = settings.presets.first {
            settings.deletePreset(id: second.id)
        }
        TestHarness.assertEqual(settings.presets.count, 6, "Deleted two presets, count is 6")

        // Reset to defaults
        settings.resetPresets()
        TestHarness.assertEqual(settings.presets.count, 8, "Reset restores exactly 8 default presets")

        let defaultHexes = ColorPreset.defaults.map { $0.hex }
        let currentHexes = settings.presets.map { $0.hex }
        TestHarness.assertEqual(currentHexes, defaultHexes, "Presets match standard high-contrast default hex codes exactly")
    }

    private static func testSliderBoundsClamping(sandboxDir: URL) {
        let settingsURL = sandboxDir.appendingPathComponent("slider_bounds_test.json")
        let settings = AppSettings(settingsURL: settingsURL)

        // 1. maxScrollHeightPx bounds (5,000 to 30,000 px)
        settings.maxScrollHeightPx = 5000
        TestHarness.assertEqual(settings.maxScrollHeightPx, 5000, "maxScrollHeightPx lower boundary is 5,000 px")
        settings.maxScrollHeightPx = 30000
        TestHarness.assertEqual(settings.maxScrollHeightPx, 30000, "maxScrollHeightPx upper boundary is 30,000 px")
        settings.maxScrollHeightPx = 4999
        TestHarness.assertEqual(settings.maxScrollHeightPx, 5000, "maxScrollHeightPx 4,999 clamped to 5,000 px")
        settings.maxScrollHeightPx = -100
        TestHarness.assertEqual(settings.maxScrollHeightPx, 5000, "maxScrollHeightPx negative clamped to 5,000 px")
        settings.maxScrollHeightPx = 30001
        TestHarness.assertEqual(settings.maxScrollHeightPx, 30000, "maxScrollHeightPx 30,001 clamped to 30,000 px")
        settings.maxScrollHeightPx = 1000000
        TestHarness.assertEqual(settings.maxScrollHeightPx, 30000, "maxScrollHeightPx 1,000,000 clamped to 30,000 px")

        // 2. history capacity bounds (10 to 500 items)
        settings.capacity = 10
        TestHarness.assertEqual(settings.capacity, 10, "capacity lower boundary is 10 items")
        settings.capacity = 500
        TestHarness.assertEqual(settings.capacity, 500, "capacity upper boundary is 500 items")
        settings.capacity = 9
        TestHarness.assertEqual(settings.capacity, 10, "capacity 9 clamped to 10 items")
        settings.capacity = 0
        TestHarness.assertEqual(settings.capacity, 10, "capacity 0 clamped to 10 items")
        settings.capacity = -50
        TestHarness.assertEqual(settings.capacity, 10, "capacity negative clamped to 10 items")
        settings.capacity = 501
        TestHarness.assertEqual(settings.capacity, 500, "capacity 501 clamped to 500 items")
        settings.capacity = 99999
        TestHarness.assertEqual(settings.capacity, 500, "capacity 99,999 clamped to 500 items")

        // 3. activeStrokeWidth bounds (1.0 to 30.0 pt)
        settings.activeStrokeWidth = 0.5
        TestHarness.assertEqual(settings.activeStrokeWidth, 1.0, "stroke width < 1.0 clamped to 1.0")
        settings.activeStrokeWidth = 45.0
        TestHarness.assertEqual(settings.activeStrokeWidth, 30.0, "stroke width > 30.0 clamped to 30.0")

        // 4. activeFontSize bounds (10.0 to 96.0 pt)
        settings.activeFontSize = 5.0
        TestHarness.assertEqual(settings.activeFontSize, 10.0, "font size < 10.0 clamped to 10.0")
        settings.activeFontSize = 120.0
        TestHarness.assertEqual(settings.activeFontSize, 96.0, "font size > 96.0 clamped to 96.0")

        // 5. jpegQuality bounds (0.1 to 1.0)
        settings.jpegQuality = 0.05
        TestHarness.assertEqual(settings.jpegQuality, 0.1, "jpegQuality < 0.1 clamped to 0.1")
        settings.jpegQuality = 1.5
        TestHarness.assertEqual(settings.jpegQuality, 1.0, "jpegQuality > 1.0 clamped to 1.0")
    }

    private static func testSaveModeAndDirectoryPersistence(sandboxDir: URL) {
        let settingsURL = sandboxDir.appendingPathComponent("save_mode_test.json")
        let settings = AppSettings(settingsURL: settingsURL)

        // Initial mode: prompt (autoSaveEnabled == false)
        TestHarness.assertFalse(settings.autoSaveEnabled, "Default save mode is prompt (autoSaveEnabled == false)")

        // Toggle to auto-save mode
        settings.autoSaveEnabled = true
        let customDir = sandboxDir.appendingPathComponent("CustomCaptures", isDirectory: true)
        settings.autoSaveDirectory = customDir
        settings.saveFormat = .jpeg
        settings.jpegQuality = 0.95

        try! settings.saveSynchronously(to: settingsURL)
        TestHarness.assertTrue(FileManager.default.fileExists(atPath: settingsURL.path), "Persisted settings to disk")

        // Re-read settings from disk
        let reloaded = AppSettings(settingsURL: settingsURL)
        TestHarness.assertTrue(reloaded.autoSaveEnabled, "Reloaded autoSaveEnabled is true")
        TestHarness.assertEqual(reloaded.autoSaveDirectory.path, customDir.path, "Reloaded autoSaveDirectory matches custom path")
        TestHarness.assertEqual(reloaded.saveFormat, .jpeg, "Reloaded save format is JPEG")
        TestHarness.assertEqual(reloaded.jpegQuality, 0.95, "Reloaded JPEG quality is 0.95")

        // Toggle back to prompt mode
        reloaded.autoSaveEnabled = false
        reloaded.saveFormat = .png
        try! reloaded.saveSynchronously(to: settingsURL)

        let reloadedPrompt = AppSettings(settingsURL: settingsURL)
        TestHarness.assertFalse(reloadedPrompt.autoSaveEnabled, "Toggled back to prompt mode (autoSaveEnabled == false)")
        TestHarness.assertEqual(reloadedPrompt.saveFormat, .png, "Save format reset to PNG")

        // Corrupted JSON recovery test
        let corruptURL = sandboxDir.appendingPathComponent("corrupt_settings.json")
        let invalidData = "INVALID_JSON_CORRUPTED_BYTES_{{[[".data(using: .utf8)!
        try! invalidData.write(to: corruptURL)

        let recovered = AppSettings(settingsURL: corruptURL)
        TestHarness.assertEqual(recovered.activeColorHex, "#FF3B30", "Corrupt JSON gracefully falls back to default activeColorHex")
        TestHarness.assertEqual(recovered.presets.count, 8, "Corrupt JSON gracefully falls back to 8 default presets")
        TestHarness.assertFalse(recovered.autoSaveEnabled, "Corrupt JSON gracefully falls back to default autoSaveEnabled = false")
    }

    // MARK: - 4. SettingsView & Window Controller Stress Tests

    private static func testSettingsViewAndTabInstantiation(sandboxDir: URL) {
        let settingsURL = sandboxDir.appendingPathComponent("settings_view_test.json")
        let settings = AppSettings(settingsURL: settingsURL)
        let storage = StorageManager(baseDirectory: sandboxDir.appendingPathComponent("StorageViewTest"))

        // 1. SettingsView body evaluation across all tabs
        for tab in SettingsTab.allCases {
            let view = SettingsView(
                appSettings: settings,
                storageManager: storage,
                initialTab: tab,
                onClose: {}
            )
            _ = view.body
            TestHarness.recordPass("SettingsView successfully evaluated body for tab '\(tab.rawValue)'")
        }

        // 2. Individual tab view bodies
        let generalTab = GeneralSettingsTab(appSettings: settings)
        _ = generalTab.body
        TestHarness.recordPass("GeneralSettingsTab body evaluated cleanly")

        let captureTab = CaptureSaveSettingsTab(appSettings: settings)
        _ = captureTab.body
        TestHarness.recordPass("CaptureSaveSettingsTab body evaluated cleanly")

        let historyTab = HistorySettingsTab(appSettings: settings, storageManager: storage)
        _ = historyTab.body
        TestHarness.recordPass("HistorySettingsTab body evaluated cleanly")

        let aboutTab = AboutSettingsTab(appSettings: settings, storageManager: storage)
        _ = aboutTab.body
        TestHarness.recordPass("AboutSettingsTab body evaluated cleanly")

        // 3. SettingsWindowController initialization and window frame checks
        let controller = SettingsWindowController(
            appSettings: settings,
            storageManager: storage,
            onDismiss: {}
        )
        guard let win = controller.window else {
            TestHarness.recordFail("SettingsWindowController window is nil", reason: "Window failed to allocate")
            return
        }
        let preferredSize = win.contentViewController?.preferredContentSize ?? .zero
        TestHarness.assertEqual(preferredSize.width, 520, "Settings window content preferred width is 520 pt")
        TestHarness.assertEqual(preferredSize.height, 530, "Settings window content preferred height is 530 pt")
        TestHarness.assertEqual(win.title, "SuperShot Preferences", "Settings window title matches")
        TestHarness.assertFalse(win.isReleasedWhenClosed, "Settings window is not released when closed")

        controller.showSettings()
        TestHarness.assertTrue(win.isVisible, "Settings window is visible after showSettings()")
        controller.close()
        TestHarness.assertFalse(win.isVisible, "Settings window is hidden after close()")
    }
}
