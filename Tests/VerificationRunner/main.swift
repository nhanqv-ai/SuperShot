import Foundation
import AppKit
import SuperShotCore
import SuperShot

@main
struct VerificationRunner {
    static func main() {
        print("\u{001B}[1;36m==================================================\u{001B}[0m")
        print("\u{001B}[1;36m  SuperShot Automated Verification Runner         \u{001B}[0m")
        print("\u{001B}[1;36m  Isolated Sandbox Mode (0 Emojis Invariant)     \u{001B}[0m")
        print("\u{001B}[1;36m==================================================\u{001B}[0m")

        let sandboxURL = TestHarness.createSandbox()
        print("Sandbox provisioned at: \(sandboxURL.path)")

        defer {
            TestHarness.cleanupSandbox(sandboxURL)
            print("Sandbox purged safely. Real ~/Library untouched.")
        }

        let startTimestamp = Date()
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // 1. ColorPreset & Palette Tests (M1)
        ColorPresetTests.run(sandboxDir: sandboxURL.appendingPathComponent("ColorPresetTest"))

        // 2. StorageManager & Sandbox Persistence Tests (M1)
        StorageManagerTests.run(sandboxDir: sandboxURL.appendingPathComponent("StorageTest"))

        // 3. AppSettings Store Tests (M1)
        AppSettingsTests.run(sandboxDir: sandboxURL.appendingPathComponent("AppSettingsTest"))

        // 4. ShotItem Model & Metadata Serialization Tests (M1)
        ShotItemTests.run()

        // 5. Localization & Dynamic Multilingual Tests (M1)
        LocalizationTests.run(sandboxDir: sandboxURL.appendingPathComponent("LocalizationTest"))

        // 6. HotKeyManager & Carbon Shortcut Tests (M1)
        HotKeyManagerTests.run()

        // 7. Build Integrity & Packaging Specification Tests
        BuildIntegrityTests.run(sandboxDir: sandboxURL.appendingPathComponent("BuildIntegrityTest"), projectRoot: projectRoot)

        // 8. Capture Overlay & Multi-Display Subsystem Tests (M2)
        CaptureOverlayTests.run()

        // 9. AnnotationEngine Vector Tools & Hit-testing Tests (M2)
        AnnotationEngineTests.run()

        // 10. Floating Toolbars & Color Palette Tests (M2)
        FloatingToolbarsTests.run()

        // 11. ImageStitcher Offset & Sticky Dedup Tests (M3)
        ImageStitcherTests.run()

        // 12. ScrollingCaptureManager & Live Preview Tests (M3)
        ScrollingCaptureTests.run()

        // 13. StatusItemManager & Context Menu Tests (M4)
        StatusItemTests.run(sandboxDir: sandboxURL.appendingPathComponent("StatusItemTest"))

        // 14. HistoryPopover & Navigation Tests (M4)
        HistoryPopoverTests.run(sandboxDir: sandboxURL.appendingPathComponent("HistoryPopoverTest"))

        // 15. AutoPasteService & Synthetic Key Injection Tests (M4)
        AutoPasteTests.run()

        // 16. SettingsView & AppSettings Tests (M4)
        SettingsViewTests.run(sandboxDir: sandboxURL.appendingPathComponent("SettingsViewTest"))

        // 16b. AutoPaste & Settings Empirical Stress Tests (Challenger M4.2)
        AutoPasteSettingsStressTests.run(sandboxDir: sandboxURL.appendingPathComponent("AutoPasteSettingsStressTest"))

        // 16c. UpdateManager & GitHub Releases Verification Tests (M7.1)
        UpdateManagerTests.run(sandboxDir: sandboxURL.appendingPathComponent("UpdateManagerTest"))

        // 17. Tier 2: Boundary & Corner Cases Tests
        BoundaryTests.run(sandboxDir: sandboxURL.appendingPathComponent("BoundaryTest"))

        // 18. Tier 3: Pairwise Combinations & Cross-Feature Interaction Tests
        PairwiseTests.run(sandboxDir: sandboxURL.appendingPathComponent("PairwiseTest"))

        // 19. Tier 4: Real-World Workload Scenarios Tests
        WorkloadTests.run(sandboxDir: sandboxURL.appendingPathComponent("WorkloadTest"))

        // 20. Cycle 13 UX Polish, Ergonomics & Localization Tests (v1.0.20)
        Cycle13Tests.run(sandboxDir: sandboxURL.appendingPathComponent("Cycle13Test"))

        // 21. Cycle 14 UX Polish, Live GUI Audit & Ergonomics Tests (v1.0.21)
        Cycle14Tests.run(sandboxDir: sandboxURL.appendingPathComponent("Cycle14Test"))

        // 22. Cycle 15 UpdateManager Enhancements & UI Polish Tests (v1.0.22)
        Cycle15Tests.run(sandboxDir: sandboxURL.appendingPathComponent("Cycle15Test"))

        let elapsed = Date().timeIntervalSince(startTimestamp)
        print("\nVerification completed in \(String(format: "%.3f", elapsed)) seconds.")

        TestHarness.printSummary()

        exit(TestHarness.exitCode)
    }
}
